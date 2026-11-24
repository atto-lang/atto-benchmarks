"""Self-test the probe against host-only controls; never an Atto result."""
import http.server
import json
import socket
import threading
import unittest
import urllib.parse
import urllib.request

import check_contract as probe


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class ProbeTests(unittest.TestCase):
    def exercise(self, mode):
        source_port = free_port()

        class Control(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urllib.parse.urlsplit(self.path)
                route = parsed.path.rsplit("/", 1)[-1]
                symbol = urllib.parse.parse_qs(parsed.query)["symbol"][0]
                path = "/element.json" if route == "element" else "/shells.json"
                if mode == "canned":
                    data = probe.ELEMENTS if route == "element" else probe.SHELLS
                else:
                    url = f"http://127.0.0.1:{source_port}{path}"
                    with urllib.request.urlopen(url, timeout=5) as response:
                        data = json.load(response)
                    if mode == "double":
                        with urllib.request.urlopen(url, timeout=5) as response:
                            response.read()
                payload = data[symbol] if route == "element" else {"shells": data[symbol]}
                if mode == "wrong":
                    payload = {"wrong": True}
                body = json.dumps(payload).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Control) as app:
            worker = threading.Thread(target=app.serve_forever, daemon=True)
            worker.start()
            try:
                probe.run(f"http://127.0.0.1:{app.server_port}", source_port)
            finally:
                app.shutdown()
                worker.join()

    def test_live_io(self):
        self.exercise("live")

    def test_canned_rejected(self):
        with self.assertRaisesRegex(AssertionError, "one upstream fetch"):
            self.exercise("canned")

    def test_double_fetch_rejected(self):
        with self.assertRaisesRegex(AssertionError, "one upstream fetch"):
            self.exercise("double")

    def test_wrong_response_rejected(self):
        with self.assertRaisesRegex(AssertionError, "expected.*got"):
            self.exercise("wrong")


if __name__ == "__main__":
    unittest.main()
