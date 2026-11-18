"""Ephemeral loopback TLS test fixture. Never changes system or SDK trust stores."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading


class TLSFixture:
    def __init__(self, port=18443):
        self.requested_port = port
        self._directory = None
        self._server = None
        self._thread = None
        self._lock = threading.Lock()
        self._hits = 0
        self._attempts = 0

    @property
    def hits(self):
        with self._lock:
            return self._hits

    @property
    def attempts(self):
        with self._lock:
            return self._attempts

    @property
    def port(self):
        if self._server is None:
            raise RuntimeError('TLS fixture not started')
        return self._server.server_port

    @property
    def certpath(self):
        if self._directory is None:
            raise RuntimeError('TLS fixture not started')
        return Path(self._directory) / 'certificate.pem'

    def start(self):
        if self._server is not None or self._directory is not None:
            raise RuntimeError('TLS fixture already started')
        self._directory = tempfile.mkdtemp(prefix='madcore-tls-')
        Path(self._directory).chmod(0o700)
        try:
            key = Path(self._directory) / 'key.pem'
            # Pre-create with private permissions so openssl never creates a readable key.
            key.touch(mode=0o600)
            print("FIXTURE_STAGE_CERTIFICATE_GENERATION", flush=True)
            subprocess.run([
                'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                '-keyout', str(key), '-out', str(self.certpath), '-days', '1',
                '-subj', '/CN=MadCore ephemeral loopback test',
                '-addext', 'subjectAltName=IP:127.0.0.1,IP:10.0.2.2',
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            print("FIXTURE_STAGE_CERTIFICATE_READY", flush=True)
            key.chmod(0o600)
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(str(self.certpath), str(key))
            owner = self

            class Handler(BaseHTTPRequestHandler):
                protocol_version = 'HTTP/1.1'

                def log_message(self, *args):
                    pass

                def do_GET(self):
                    if self.path not in ('/ok', '/tls-probe'):
                        self.send_error(404)
                        return
                    if self.path == '/tls-probe':
                        with owner._lock:
                            owner._hits += 1
                    self.send_response(200)
                    self.send_header('Content-Length', '5')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    self.wfile.write(b'hello')
                    self.close_connection = True

            class Server(ThreadingHTTPServer):
                # A client withholding TLS handshake bytes must not block shutdown.
                daemon_threads = True

                def get_request(self):
                    connection, address = self.socket.accept()
                    with owner._lock:
                        owner._attempts += 1
                    connection.settimeout(2)
                    try:
                        return context.wrap_socket(connection, server_side=True), address
                    except BaseException:
                        connection.close()
                        raise

            self._server = Server(('127.0.0.1', self.requested_port), Handler)
            self._thread = threading.Thread(target=self._server.serve_forever,
                                            kwargs={'poll_interval': 0.05}, daemon=True)
            self._thread.start()
            print("FIXTURE_STAGE_TLS_LISTENING", flush=True)
            with self._lock:
                self._hits = 0
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        server, thread = self._server, self._thread
        self._server = None
        self._thread = None
        try:
            if server is not None:
                if thread is not None and thread.is_alive():
                    server.shutdown()
                server.server_close()
            if thread is not None:
                thread.join(timeout=5)
                if thread.is_alive():
                    raise RuntimeError('TLS fixture shutdown timed out')
        finally:
            if self._directory is not None:
                shutil.rmtree(self._directory)
                self._directory = None

    def __enter__(self):
        return self.start()

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()
