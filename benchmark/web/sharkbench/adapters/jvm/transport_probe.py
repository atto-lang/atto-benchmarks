"""Transport admission only: no benchmark scores or JSON guest proof."""
import collections
import concurrent.futures
import http.server
import json
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:5001"
PATH = "/transport-smoke"


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with self.server.lock:
            self.server.counts[self.path] += 1
            status, body = self.server.reply
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # expected if guest rejects an oversized body

    def log_message(self, *_args):
        pass


def request(path=PATH, method="GET"):
    req = urllib.request.Request(BASE + path, method=method)
    try:
        response = urllib.request.urlopen(req, timeout=8)
    except urllib.error.HTTPError as exc:
        response = exc
    with response:
        return response.status, response.read()


def expect(path, method, code, body=None):
    actual, payload = request(path, method)
    if actual != code or (body is not None and payload != body):
        raise AssertionError((path, method, code, body, actual, payload[:256]))


def run(command):
    # Refuse to test an unrelated server already occupying the app port.
    import socket
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 5001))
    with http.server.ThreadingHTTPServer(("127.0.0.1", 5002), Fixture) as source:
        source.lock = threading.Lock()
        source.counts = collections.Counter()
        source.reply = (200, b'{"He":{"name":"Helium","number":2,"group":18}}')
        worker = threading.Thread(target=source.serve_forever, daemon=True)
        worker.start()
        child = None
        try:
            child = subprocess.Popen(command)
            deadline = time.monotonic() + 90
            while True:
                if child.poll() is not None:
                    raise RuntimeError(f"guest exited during startup: {child.returncode}")
                try:
                    expect("/not-a-route", "GET", 404)
                    break
                except urllib.error.URLError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError("guest did not start within 90s")
                    time.sleep(0.2)
            expect(PATH, "POST", 405)
            with source.lock:
                if source.counts:
                    raise AssertionError("invalid routes contacted upstream")
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                futures = [pool.submit(expect, PATH, "GET", 200, b"transport-only")
                           for _ in range(32)]
                for future in futures:
                    future.result()
            for reply in [(503, b"unavailable"), (200, b""), (200, b"x" * 131073)]:
                with source.lock:
                    source.reply = reply
                expect(PATH, "GET", 502)
            with source.lock:
                source.reply = (200, b"{}")
            expect(PATH, "GET", 200, b"transport-only")
            with source.lock:
                counts = dict(source.counts)
            if counts != {"/element.json": 36}:
                raise AssertionError(f"unexpected upstream counts: {counts}")
            if child.poll() is not None:
                raise RuntimeError("guest exited before completion")
            print(json.dumps({"status": "PASS", "scope": "transport_only",
                              "concurrent_successes": 32, "fault_cases": 3,
                              "recovery_successes": 1, "upstream_requests": counts}))
        finally:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            source.shutdown()
            worker.join()


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] != "--":
        raise SystemExit("usage: transport_probe.py -- COMMAND [ARGS...]")
    run(sys.argv[2:])
