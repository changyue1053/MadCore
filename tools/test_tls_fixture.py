"""Test TLS fixture controls only, not an Android/iOS/Harmony SDK transport."""
import http.client
import socket
import ssl
import stat
from tls_fixture import TLSFixture


def get(fixture, context, path):
    connection = http.client.HTTPSConnection('127.0.0.1', fixture.port,
                                              context=context, timeout=5)
    try:
        connection.request('GET', path)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


with TLSFixture(port=0) as fixture:
    directory = fixture.certpath.parent
    assert stat.S_IMODE(directory.stat().st_mode) == 0o700
    assert stat.S_IMODE((directory / 'key.pem').stat().st_mode) == 0o600
    try:
        get(fixture, ssl.create_default_context(), '/tls-probe')
    except ssl.SSLCertVerificationError:
        pass
    else:
        raise AssertionError('Default TLS trust unexpectedly accepted ephemeral certificate')
    assert fixture.hits == 0
    # Only this test-local context trusts the temporary certificate; verification stays enabled.
    trusted = ssl.create_default_context(cafile=str(fixture.certpath))
    assert trusted.check_hostname and trusted.verify_mode == ssl.CERT_REQUIRED
    assert get(fixture, trusted, '/ok') == (200, b'hello')
    assert fixture.hits == 0
    assert get(fixture, trusted, '/tls-probe') == (200, b'hello')
    assert fixture.hits == 1
assert not directory.exists()
fixture.close()  # Idempotent cleanup.
print('Ephemeral TLS fixture trust controls passed; no SDK transport or system trust changes')


def require_rejection(action, exception):
    try:
        action()
    except exception:
        return
    raise AssertionError('TLS test unexpectedly succeeded')


with TLSFixture(port=0, android_trusted=True) as good, TLSFixture(port=0) as bad:
    trusted = ssl.create_default_context(cafile=str(good.ca_path))
    assert trusted.check_hostname and trusted.verify_mode == ssl.CERT_REQUIRED
    assert b'PRIVATE KEY' not in good.ca_path.read_bytes()
    chain_directory = good.ca_path.parent
    assert stat.S_IMODE(chain_directory.stat().st_mode) == 0o700
    for name in ('key.pem', 'ca-key.pem'):
        assert stat.S_IMODE((chain_directory / name).stat().st_mode) == 0o600
    require_rejection(lambda: get(good, ssl.create_default_context(), '/tls-probe'),
                      ssl.SSLCertVerificationError)
    require_rejection(lambda: get(bad, trusted, '/tls-probe'), ssl.SSLCertVerificationError)
    assert good.hits == bad.hits == 0
    with socket.create_connection(('127.0.0.1', good.port), timeout=5) as raw:
        with trusted.wrap_socket(raw, server_hostname='10.0.2.2') as wrapped:
            assert wrapped.version() == 'TLSv1.2'

    def connect_as(host, context):
        with socket.create_connection(('127.0.0.1', good.port), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname=host):
                pass

    require_rejection(lambda: connect_as('wrong.invalid', trusted), ssl.SSLCertVerificationError)
    tls13 = ssl.create_default_context(cafile=str(good.ca_path))
    tls13.minimum_version = ssl.TLSVersion.TLSv1_3
    require_rejection(lambda: connect_as('127.0.0.1', tls13), ssl.SSLError)
    assert get(good, trusted, '/ok') == (200, b'hello')
    assert good.hits == 0
    assert get(good, trusted, '/tls-probe') == (200, b'hello')
    assert good.hits == 1 and bad.hits == 0
assert not chain_directory.exists()
print('Android fixture TLS 1.2, exact IP SAN, distinct CA and teardown checks passed; not SDK runtime')
