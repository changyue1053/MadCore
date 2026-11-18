"""Loopback-only deterministic fixture for hosted iOS Simulator tests; no credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
import threading

redirect_lock = threading.Lock()
redirect_hits = 0

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_GET(self):
        global redirect_hits
        if self.path in ('/redirect-target', '/redirect-count'):
            with redirect_lock:
                if self.path == '/redirect-target': redirect_hits += 1
                body = str(redirect_hits).encode('ascii')
            self.send_response(200)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == '/slow': time.sleep(1)
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/redirect-target')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.path == '/chunked':
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write(b'14\r\n' + b'x' * 20 + b'\r\n0\r\n\r\n')
            return
        body = b'bad' if self.path == '/error' else b'hello'
        self.send_response(400 if self.path == '/error' else 200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.send_response(201)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18082), Handler).serve_forever()
