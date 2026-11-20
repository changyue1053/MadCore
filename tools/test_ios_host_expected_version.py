import json
from pathlib import Path
import plistlib
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from configure_ios_host_version import KEY, configure


class ExpectedVersionTest(unittest.TestCase):
    def test_default_reads_authority_and_explicit_mismatch_is_not_overwritten(self):
        for explicit, expected in [(None, '0.1.0-SNAPSHOT'), ('0.1.0-rehearsal.2', '0.1.0-rehearsal.2')]:
            with self.subTest(explicit=explicit), TemporaryDirectory() as temp:
                root = Path(temp)
                manifest = root / 'manifest.json'
                plist = root / 'Info.plist'
                manifest.write_text(json.dumps({'version': '0.1.0-SNAPSHOT'}))
                plist.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'test.example'}))
                configure(manifest, plist, explicit)
                self.assertEqual(plistlib.loads(plist.read_bytes()),
                                 {'CFBundleIdentifier': 'test.example', KEY: expected})
                self.assertEqual(json.loads(manifest.read_bytes())['version'], '0.1.0-SNAPSHOT')

    def test_invalid_value_never_falls_back_or_overwrites_the_plist(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / 'manifest.json'
            plist = root / 'Info.plist'
            manifest.write_text(json.dumps({'version': '0.1.0-SNAPSHOT'}))
            original = plistlib.dumps({'CFBundleIdentifier': 'test.example'})
            plist.write_bytes(original)
            for invalid in ('', 'latest.release', '17', '001.0.0', '1.0.0-foo..bar', '1.0.0-é'):
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    configure(manifest, plist, invalid)
                self.assertEqual(plist.read_bytes(), original)
            repeated = plistlib.dumps({KEY: 'old'})
            plist.write_bytes(repeated)
            with self.assertRaises(ValueError):
                configure(manifest, plist)
            self.assertEqual(plist.read_bytes(), repeated)

    def test_cli_hides_malformed_manifest_values(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / 'manifest.json'
            plist = root / 'Info.plist'
            manifest.write_text('private malformed content')
            plist.write_bytes(plistlib.dumps({}))
            result = subprocess.run([sys.executable, '-B', str(Path(__file__).with_name(
                'configure_ios_host_version.py')), str(manifest), str(plist)],
                text=True, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, 'Cannot set independent iOS test host version expectation\n')


if __name__ == '__main__':
    unittest.main()
