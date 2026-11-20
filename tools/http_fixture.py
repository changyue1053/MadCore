"""Loopback-only deterministic fixture for hosted iOS Simulator tests; no credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
import threading

redirect_lock = threading.Lock()
redirect_hits = 0
tls_fixture = None
android_tls_fixture = None

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *args): pass
    def do_GET(self):
        global redirect_hits
        if self.path in ('/tls-ready', '/tls-count', '/tls-attempts'):
            body = (str(tls_fixture.attempts) if self.path == '/tls-attempts' and tls_fixture else str(tls_fixture.hits) if self.path == '/tls-count' and tls_fixture else 'ready' if tls_fixture else 'unavailable').encode('ascii')
            self.send_response(200 if tls_fixture else 503)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path == '/android-tls-count':
            body = str(android_tls_fixture.hits).encode('ascii') if android_tls_fixture else b'unavailable'
            self.send_response(200 if android_tls_fixture else 503)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
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
        if self.path == '/bridge-headers': self.send_header('X-Madcore-Test', 'present')
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def method_echo(self):
        length = int(self.headers.get('Content-Length', '0'))
        if length < 0 or length > 1048576:
            self.send_error(413)
            return
        body = self.command.encode('ascii') + b':' + self.rfile.read(length)
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_PUT(self): self.method_echo()
    def do_DELETE(self): self.method_echo()
    def do_POST(self):
        if self.path == '/bridge-echo':
            if self.headers.get('X-Copied-Request') != 'probe':
                self.send_error(400); return
            self.method_echo(); return
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.send_response(201)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

if __name__ == '__main__':
    import argparse
    import signal
    def terminate(signum, frame): raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    from contextlib import ExitStack
    from pathlib import Path
    from tls_fixture import TLSFixture
    parser = argparse.ArgumentParser()
    parser.add_argument('--tls', action='store_true')
    parser.add_argument('--android-ca', type=Path, metavar='PUBLIC_CA_DESTINATION')
    args = parser.parse_args()
    if args.android_ca is not None and not args.tls:
        parser.error('--android-ca requires --tls')
    print("FIXTURE_STAGE_TLS_START" if args.tls else "FIXTURE_STAGE_HTTP_ONLY", flush=True)
    with ExitStack() as cleanup:
        if args.tls:
            tls_fixture = cleanup.enter_context(TLSFixture())
        if args.android_ca is not None:
            android_tls_fixture = cleanup.enter_context(TLSFixture(port=28443, android_trusted=True))
            # Export the public trust anchor once, only to the caller's disposable Debug tree.
            with args.android_ca.open('xb') as destination:
                destination.write(android_tls_fixture.ca_path.read_bytes())
        server = cleanup.enter_context(ThreadingHTTPServer(('127.0.0.1', 18082), Handler))
        print('FIXTURE_STAGE_LISTENING_18082', flush=True)
        server.serve_forever()
