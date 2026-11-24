"""Host-only control tests for transport_probe; not Atto execution."""
import contextlib
import io
import json
import socket
import sys
import unittest

import transport_probe as probe

CONTROL = r'''
import http.server
import urllib.request
import urllib.error
import sys

mode = sys.argv[1]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.reply(405, b"GET required")
    def do_GET(self):
        if self.path != "/transport-smoke":
            self.reply(404, b"not found")
            return
        if mode == "canned":
            self.reply(200, b"transport-only")
            return
        if mode == "redirect":
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:1/")
            self.end_headers()
            return
        if mode == "oversized":
            self.reply(200, b"x" * 4097)
            return
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
                "http://127.0.0.1:5002/element.json", timeout=5) as upstream:
            body = upstream.read(131073)
        self.reply(200, b"transport-only") if 0 < len(body) <= 131072 else self.reply(502, b"invalid")
    def reply(self, status, body):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

class SafeHandler(Handler):
    def do_GET(self):
        try:
            super().do_GET()
        except urllib.error.HTTPError:
            self.reply(502, b"upstream status")

class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 32

with Server(("127.0.0.1", 5001), SafeHandler) as server:
    server.serve_forever()
'''


class TransportControls(unittest.TestCase):
    def invoke(self, mode):
        probe.run([sys.executable, "-c", CONTROL, mode])

    def test_live_boundary_and_recovery(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.invoke("live")
        receipt = json.loads(output.getvalue().strip().splitlines()[-1])
        self.assertEqual(receipt["upstream_requests"], {"/element.json": 37})
        self.assertEqual(receipt["concurrent_successes"], 32)
        self.assertEqual(receipt["boundary_successes"], 1)
        self.assertEqual(receipt["fault_cases"], 3)

    def test_canned_fails_fault_gate(self):
        with self.assertRaises(AssertionError):
            self.invoke("canned")

    def test_redirect_rejected(self):
        with self.assertRaisesRegex(AssertionError, "unexpected redirect"):
            self.invoke("redirect")

    def test_oversize_rejected(self):
        with self.assertRaisesRegex(AssertionError, "exceeds limit"):
            self.invoke("oversized")

    def test_occupied_port_rejected(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 5001))
            sock.listen()
            with self.assertRaises(OSError):
                self.invoke("live")


if __name__ == "__main__":
    unittest.main()
