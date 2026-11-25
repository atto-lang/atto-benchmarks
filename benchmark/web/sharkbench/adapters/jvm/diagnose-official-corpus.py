#!/usr/bin/env python3
"""Diagnostic only: actual official corpus, no official performance claim."""
import concurrent.futures
import http.client
import json
import pathlib
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

def run(data):
    raw = {kind: (data / (kind + ".json")).read_bytes()
           for kind in ("element", "shells")}
    documents = {kind: json.loads(body) for kind, body in raw.items()}
    counts = {"element": 0, "shells": 0}
    lock = threading.Lock()

    class Source(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        def log_message(self, *_): pass
        def do_GET(self):
            kind = self.path.removeprefix("/").removesuffix(".json")
            if self.path not in ("/element.json", "/shells.json"):
                self.send_error(404)
                return
            with lock:
                counts[kind] += 1
            body = raw[kind]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    jobs = [(kind, symbol) for kind in ("element", "shells")
            for symbol in sorted(documents[kind])]
    # Interleave routes and distribute across the complete corpus.
    first = [(kind, sorted(documents[kind])[i * len(documents[kind]) // 16])
             for i in range(16) for kind in ("element", "shells")]
    gate = threading.Barrier(32, timeout=10)
    def request(job, cold=False):
        kind, symbol = job
        if cold:
            gate.wait()
        start = time.monotonic()
        conn = http.client.HTTPConnection("127.0.0.1", 5001, timeout=15)
        try:
            conn.request("GET", f"/api/v1/periodic-table/{kind}?symbol={symbol}")
            resp = conn.getresponse()
            body = resp.read(16385)
            expected = documents[kind][symbol]
            if kind == "element":
                expected = {key: expected[key] for key in ("name", "number", "group")}
            else:
                expected = {"shells": expected}
            ok = (resp.status == 200 and len(body) <= 16384
                  and json.loads(body) == expected)
            return (kind, symbol, resp.status, round((time.monotonic()-start)*1000), ok,
                    "" if ok else repr(body[:180]))
        except Exception as exc:
            return (kind, symbol, 0, round((time.monotonic()-start)*1000), False, repr(exc))
        finally:
            conn.close()

    with ThreadingHTTPServer(("127.0.0.1", 5002), Source) as server:
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
                results = list(pool.map(lambda job: request(job, True), first))
            for result in results:
                print("COLD_RESULT", *result, flush=True)
            print("COLD_SUMMARY", json.dumps({"requests":len(results),
                "ok":sum(r[4] for r in results),
                "within_2s":sum(r[4] and r[3]<2000 for r in results),
                "max_ms":max(r[3] for r in results),"upstream":counts}), flush=True)
            assert all(r[4] for r in results), "cold official corpus response mismatch"
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(request, jobs))
            for result in results:
                if not result[4]:
                    print("CORPUS_FAILURE", *result, flush=True)
            expected_counts = {kind:16+len(documents[kind]) for kind in counts}
            print("CORPUS_SUMMARY", json.dumps({"requests":len(results),
                "ok":sum(r[4] for r in results),"upstream":counts,
                "expected_upstream":expected_counts}), flush=True)
            assert all(r[4] for r in results) and counts == expected_counts
            print("PASS: complete upstream corpus diagnostic; not a benchmark score", flush=True)
        finally:
            server.shutdown()
            thread.join(timeout=3)

if __name__ == "__main__":
    run(pathlib.Path(sys.argv[1]))
