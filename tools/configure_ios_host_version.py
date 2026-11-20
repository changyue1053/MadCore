"""Set independent test-host runtime expectation, not a packaged SDK field."""
import argparse
import json
from pathlib import Path
import plistlib
import re

KEY = 'MadCoreExpectedSdkVersion'
VERSION = re.compile(r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*)?')


def configure(manifest, info_plist, override=None):
    version = override
    if version is None:
        try:
            version = json.loads(manifest.read_bytes())['version']
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise ValueError('expected-version-manifest-invalid') from error
    if not isinstance(version, str) or len(version) > 64 or not VERSION.fullmatch(version):
        raise ValueError('expected-version-invalid')
    info = plistlib.loads(info_plist.read_bytes())
    if not isinstance(info, dict) or KEY in info:
        raise ValueError('expected-version-test-plist-invalid')
    info[KEY] = version
    info_plist.write_bytes(plistlib.dumps(info))


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('test_host_info_plist', type=Path)
    parser.add_argument('--expected-version')
    args = parser.parse_args()
    try:
        configure(args.manifest, args.test_host_info_plist, args.expected_version)
    except (OSError, ValueError, plistlib.InvalidFileException):
        # Never report values or filesystem details to CI on malformed inputs.
        parser.exit(1, 'Cannot set independent iOS test host version expectation\n')


if __name__ == '__main__':
    main()
