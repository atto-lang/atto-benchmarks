#!/usr/bin/env python3
"""Correctness-only SharkBench adapter probe; never emits performance scores."""
import argparse
import collections
import concurrent.futures
import http.server
import json
import threading
import urllib.parse
import urllib.request

PREFIX = "/api/v1/periodic-table/"
SYMBOLS = ("H", "He", "Na", "Fe")
ELEMENTS = {
    "H": {"name": "Hydrogen", "number": 1, "group": 1},
    "He": {"name": "Helium", "number": 2, "group": 18},
    "Na": {"name": "Sodium", "number": 11, "group": 1},
    "Fe": {"name": "Iron", "number": 26, "group": 8},
}
SHELLS = {"H": [1], "He": [2], "Na": [2, 8, 1], "Fe": [2, 8, 14, 2]}


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with self.server.lock:
            data = self.server.data.get(self.path)
            if data is not None:
                self.server.counts[self.path] += 1
                body = json.dumps(data).encode("utf-8")
        if data is None:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def check_one(base, route, symbol, expected):
    url = base + PREFIX + route + "?" + urllib.parse.urlencode({"symbol": symbol})
    with urllib.request.urlopen(url, timeout=5) as response:
        if response.status != 200 or response.headers.get_content_type() != "application/json":
            raise AssertionError(f"unexpected HTTP response: {url}")
        actual = json.load(response)
    # Canonical JSON equality also distinguishes bools and numbers.
    if json.dumps(actual, sort_keys=True) != json.dumps(expected, sort_keys=True):
        raise AssertionError(f"{url}: expected {expected!r}, got {actual!r}")


def run(base, source_port):
    # Use a synthetic source to prove request-time I/O; never use it for scores.
    with http.server.ThreadingHTTPServer(("127.0.0.1", source_port), Fixture) as source:
        source.lock = threading.Lock()
        source.counts = collections.Counter()
        source.data = {}
        worker = threading.Thread(target=source.serve_forever, daemon=True)
        worker.start()
        try:
            for phase in (0, 1):
                elements = {k: dict(v) for k, v in ELEMENTS.items()}
                shells = {k: list(v) for k, v in SHELLS.items()}
                if phase:
                    # Deliberately nonphysical sentinels catch stale/canned data.
                    elements["He"]["name"] = "Helium probe changed"
                    shells["He"] = [99]
                with source.lock:
                    source.data = {"/element.json": elements, "/shells.json": shells}
                    source.counts.clear()
                jobs = [
                    (route, symbol, elements[symbol] if route == "element" else {"shells": shells[symbol]})
                    for _ in range(4)
                    for route in ("element", "shells")
                    for symbol in SYMBOLS
                ]
                with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                    futures = [pool.submit(check_one, base, *job) for job in jobs]
                    for future in futures:
                        future.result()
                with source.lock:
                    counts = dict(source.counts)
                expected = {"/element.json": 16, "/shells.json": 16}
                if counts != expected:
                    raise AssertionError(f"phase {phase}: expected one upstream fetch per request: {expected}, got {counts}")
                print(f"phase {phase}: 32 correct responses; upstream counts {counts}")
        finally:
            source.shutdown()
            worker.join()
    print("PASS: 64 correctness probes; no performance measurement")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:5001")
    parser.add_argument("--source-port", type=int, default=5002)
    args = parser.parse_args()
    run(args.base_url.rstrip("/"), args.source_port)
