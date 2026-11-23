# Static server for development. Files must be revalidated on every load: with plain http.server a browser
# may pair a new main.js with an old cached module, which broke Safari on 2026-11-22.
import functools, http.server, os, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache'); super().end_headers()
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 4180), functools.partial(H, directory=root)).serve_forever()
