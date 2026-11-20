"""Synthetic fixtures; this does not verify a real Apple build or supplier."""
import io
from pathlib import Path
import plistlib
import subprocess
import tarfile
from tempfile import TemporaryDirectory
import unittest

from capture_ios_distribution_evidence import host, package, supplier


class EvidenceTest(unittest.TestCase):
    def test_package_records_both_archives_and_privacy_bytes(self):
        with TemporaryDirectory() as dir:
            root = Path(dir)
            slices = []
            for name in ('ios-arm64', 'ios-arm64-simulator'):
                item = dict(LibraryIdentifier=name, LibraryPath='MadCore.framework',
                            SupportedPlatform='ios', SupportedArchitectures=['arm64'])
                if name.endswith('simulator'):
                    item['SupportedPlatformVariant'] = 'simulator'
                slices.append(item)
                f = root / name / 'MadCore.framework'
                (f / 'Headers').mkdir(parents=True)
                for path in ('Headers/MadCore.h', 'PrivacyInfo.xcprivacy'):
                    (f / path).write_text('synthetic')
                obj = f / 'fixture.o'
                obj.write_bytes(b'not a real Mach-O object')
                subprocess.run(['ar', '-q', str(f / 'MadCore'), str(obj), str(obj)], check=True,
                               capture_output=True)
                obj.unlink()
            (root / 'Info.plist').write_bytes(plistlib.dumps(dict(AvailableLibraries=slices)))
            evidence = package(root)
            self.assertEqual(evidence['slices']['ios-arm64']['static_archive_members'], ['fixture.o', 'fixture.o'])
            self.assertIn('ios-arm64-simulator/MadCore.framework/PrivacyInfo.xcprivacy', evidence['packaged_files'])
            slices.pop()
            (root / 'Info.plist').write_bytes(plistlib.dumps(dict(AvailableLibraries=slices)))
            with self.assertRaisesRegex(ValueError, 'exactly'):
                package(root)

    def test_link_map_checks_named_host_and_requires_sdk_member(self):
        with TemporaryDirectory() as dir:
            exe = Path(dir) / 'Host'
            exe.write_bytes(b'synthetic')
            map_file = Path(dir) / 'link.txt'
            header = '# Path: /tmp/Host\n# Arch: arm64\n# Object files:\n'
            footer = '\n# Sections:\n# Symbols:\n'
            map_file.write_text(header + '[ 1] /tmp/MadCore.framework/MadCore(foo.o)' + footer)
            self.assertIn('(foo.o)', host(exe, map_file, 'ios-arm64')['link_map_loaded_objects'][0])
            map_file.write_text(header + '[ 1] /tmp/Host.o' + footer)
            with self.assertRaisesRegex(ValueError, 'MadCore archive members'):
                host(exe, map_file, 'ios-arm64')

    def test_supplier_hashes_names_without_extraction_and_rejects_wrong_artifact(self):
        with TemporaryDirectory() as dir:
            archive = Path(dir) / 'kotlin-native-prebuilt-2.2.21-macos-aarch64.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name in ('bin/compiler', 'licenses/NOTICE.txt', 'klib/common/stdlib/default/manifest'):
                    member = tarfile.TarInfo(name)
                    member.size = 3
                    tar.addfile(member, io.BytesIO(b'abc'))
            result = supplier(archive, '2.2.21')
            self.assertEqual(result['archive_member_count'], 3)
            self.assertEqual(len(result['notice_and_klib_manifest_candidates']), 2)
            self.assertNotIn('licenses', {p.name for p in Path(dir).iterdir()})
            with self.assertRaisesRegex(ValueError, 'exact cached'):
                supplier(archive, '2.3.21')


if __name__ == '__main__':
    unittest.main()
