"""Host-only lifecycle fixture controls. Never compiler execution evidence."""
import http.server
import json
import socket
import threading
import unittest
import urllib.error
import urllib.request
import contextlib
import io

import check_lifecycle as probe


class LifecycleControls(unittest.TestCase):
    def exercise(self, mode):
        class Control(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                route = self.path.split("?", 1)[0].rsplit("/", 1)[-1]
                if route not in ("element", "shells"):
                    self.reply(404, b"missing")
                    return
                if mode == "canned":
                    data = json.loads(probe.ELEMENT if route == "element" else probe.SHELLS)
                else:
                    try:
                        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
                                "http://127.0.0.1:5002/" + route + ".json",
                                timeout=probe.DEADLINE_SECONDS) as upstream:
                            data = json.load(upstream)
                    except (TimeoutError, urllib.error.URLError):
                        self.reply(502 if mode == "wrong-deadline" else 504, b"deadline")
                        return
                body = data["He"] if route == "element" else {"shells": data["He"]}
                self.reply(200, json.dumps(body).encode(), "application/json")

            def reply(self, status, body, content_type="text/plain"):
                try:
                    self.send_response(status)
                    self.send_header("Content-Type", content_type)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, *_args):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 5001), Control) as app:
            thread = threading.Thread(target=app.serve_forever, daemon=True)
            thread.start()
            try:
                probe.run()
            finally:
                app.shutdown()
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())

    def test_live_deadline_and_recovery(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.exercise("live")
        self.assertIn("PASS: deadline, sibling progress, abandoned socket, recovery", output.getvalue())
        self.assertIn("Socket-level lifecycle proof only", output.getvalue())

    def test_canned_response_rejected_before_upstream(self):
        with self.assertRaisesRegex(AssertionError, "never reached upstream"):
            self.exercise("canned")

    def test_wrong_deadline_status_rejected(self):
        with self.assertRaisesRegex(AssertionError, "expected 504, got 502"):
            self.exercise("wrong-deadline")


if __name__ == "__main__":
    unittest.main()
