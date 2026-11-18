"""Test TLS fixture controls only, not an Android/iOS/Harmony SDK transport."""
import http.client
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
