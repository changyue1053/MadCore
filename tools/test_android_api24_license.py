"""Synthetic API24 license preflight tests; no SDK or official terms."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).with_name("check_android_api24_license.py")
XML = """<repo:sdk-repository xmlns:repo="urn:sample">
<license id="android-sdk-license">\n  Synthetic &amp; sample terms.\n</license>
<remotePackage path="system-images;android-24;default;x86_64">
  <uses-license ref="android-sdk-license"/>
  <archives><archive><complete><url>x86_64-24_r08.zip</url></complete></archive></archives>
</remotePackage></repo:sdk-repository>"""
DIGEST = hashlib.sha1(b"\n  Synthetic & sample terms.\n").hexdigest()


class LicensePreflight(unittest.TestCase):
    def run_preflight(self, acceptance, xml=XML):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / "manifest.xml"
            manifest.write_bytes(xml.encode())
            acceptance_path = root / "licenses" / "android-sdk-license"
            if acceptance is not None:
                acceptance_path.parent.mkdir()
                acceptance_path.write_bytes(acceptance.encode())
            result = subprocess.run(
                [sys.executable, str(CHECKER), str(manifest), str(root)],
                text=True, capture_output=True, timeout=10, check=False,
            )
            if acceptance is None:
                self.assertFalse(acceptance_path.exists())
            else:
                self.assertEqual(acceptance_path.read_bytes(), acceptance.encode())
            self.assertNotIn("Synthetic &", result.stdout + result.stderr)
            return result

    def test_matches_exact_existing_line_and_xml_normalization(self):
        result = self.run_preflight("0" * 40 + "\r\n" + DIGEST + "\r\n", XML.replace("\n", "\r\n"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"expected_terms_sha1={DIGEST}", result.stdout)
        self.assertIn("valid_hash_lines=2 invalid_nonempty_lines=0 exact_match=True", result.stdout)

    def test_fails_closed_if_acceptance_absent_different_or_malformed(self):
        for acceptance, expected in (
            (None, "acceptance_file_present=False"),
            ("0" * 40, "valid_hash_lines=1 invalid_nonempty_lines=0"),
            (" " + DIGEST, "valid_hash_lines=0 invalid_nonempty_lines=1"),
            (DIGEST + " annotation", "valid_hash_lines=0 invalid_nonempty_lines=1"),
            (DIGEST.upper(), "valid_hash_lines=0 invalid_nonempty_lines=1"),
        ):
            with self.subTest(acceptance=acceptance):
                result = self.run_preflight(acceptance)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, result.stdout)
                self.assertIn("exact_match=False", result.stdout)

    def test_rejects_changed_archive_license_and_malformed_xml(self):
        for xml in (XML.replace("r08", "r09"), XML.replace("android-sdk-license", "different-id"),
                    XML.replace("</license>", "<node/></license>"), "<broken"):
            with self.subTest(xml=xml):
                result = self.run_preflight(DIGEST, xml)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("exact_match=True", result.stdout)


if __name__ == "__main__":
    unittest.main()
