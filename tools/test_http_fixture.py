"""Exercise local fixture bookkeeping, not any SDK transport."""
import http.client
import threading
from http_fixture import Handler, ThreadingHTTPServer

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    def get(path):
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        try:
            connection.request('GET', path)
            response = connection.getresponse()
            return response.status, response.getheader('Location'), response.read()
        finally:
            connection.close()
    assert get('/redirect-count')[2] == b'0'
    assert get('/redirect') == (302, '/redirect-target', b'')
    assert get('/redirect-count')[2] == b'0'
    assert get('/redirect-target')[2] == b'1'
    assert get('/redirect-count')[2] == b'1'
    print('Loopback redirect fixture hit-count checks passed; not SDK transport execution')
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=3)
