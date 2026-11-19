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
    def post(path, body, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
        try:
            connection.request('POST', path, body=body, headers=headers or {})
            response = connection.getresponse()
            content = response.read()
            assert int(response.getheader('Content-Length')) == len(content)
            return response.status, content
        finally:
            connection.close()

    # Existing Android/iOS consumers require byte-for-byte POST echo and 201,
    # with no special bridge header requirement or method prefix.
    payload = b'body\x00\xff'
    assert post('/echo', payload) == (201, payload)
    assert post('/echo', payload, {'X-Copied-Request': 'anything'}) == (201, payload)
    assert post('/echo', b'') == (201, b'')
    assert post('/bridge-echo', b'body')[0] == 400
    assert post('/bridge-echo', b'body', {'X-Copied-Request': 'wrong'})[0] == 400
    assert post('/bridge-echo', b'body', {'X-Copied-Request': 'probe'}) == (200, b'POST:body')
    assert get('/redirect-count')[2] == b'0'
    assert get('/redirect') == (302, '/redirect-target', b'')
    assert get('/redirect-count')[2] == b'0'
    assert get('/redirect-target')[2] == b'1'
    assert get('/redirect-count')[2] == b'1'
    print('Loopback POST compatibility, bridge header guard and redirect checks passed; not SDK transport execution')
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=3)
