"""Host checks using synthetic archives and non-network shell shims."""
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from zipfile import ZipFile

from check_harmony_composition import check

LIBS = ['libs/arm64-v8a/libmadcore.so', 'libs/arm64-v8a/libmadcore_napi.so']
BRIDGE = 'libs/arm64-v8a/libmadcore_copied_bridge.so'
CXX = 'libs/arm64-v8a/libc++_shared.so'


class ArchiveComposition(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.alpha = self.archive('alpha.har', ['package/Index.ets'])
        self.beta = self.archive('beta.har', ['package/Index.d.ets'])
        self.core = self.archive('core.har', LIBS)
        self.hap = self.archive('entry.hap', LIBS + [CXX])

    def archive(self, name, entries, *, tar=False):
        path = self.root / name
        if tar:
            with tarfile.open(path, 'w') as archive:
                for entry in entries:
                    item = tarfile.TarInfo(entry)
                    item.size = 4
                    archive.addfile(item, io.BytesIO(b'test'))
        else:
            with ZipFile(path, 'w') as archive:
                for entry in entries:
                    archive.writestr(entry, b'test')
        return path

    def test_default_and_experimental_archive_pairs(self):
        check(self.core, self.alpha, self.beta, self.hap, 'default')
        exp = self.archive('experimental.har', LIBS + [BRIDGE], tar=True)
        exp_hap = self.archive('experimental.hap', LIBS + [BRIDGE, CXX])
        check(exp, self.alpha, self.beta, exp_hap, 'experimental')

    def test_each_archive_rejects_wrong_bridge_count(self):
        exp = self.archive('experimental.har', LIBS + [BRIDGE], tar=True)
        exp_hap = self.archive('experimental.hap', LIBS + [BRIDGE])
        duplicate = self.archive('duplicate.har', LIBS + [BRIDGE, BRIDGE], tar=True)
        duplicate_hap = self.archive('duplicate.hap', LIBS + [BRIDGE, 'other/' + BRIDGE])
        for core, hap, mode in [
            (exp, self.hap, 'default'), (self.core, exp_hap, 'default'),
            (self.core, exp_hap, 'experimental'), (exp, self.hap, 'experimental'),
            (duplicate, exp_hap, 'experimental'), (exp, duplicate_hap, 'experimental'),
        ]:
            with self.subTest(core=core.name, hap=hap.name, mode=mode):
                with self.assertRaisesRegex(ValueError, 'copies of libmadcore_copied_bridge'):
                    check(core, self.alpha, self.beta, hap, mode)

    def test_thin_upper_and_core_pair_rules_unchanged(self):
        for entries in (['package/Index.ets', 'libs/core.har'],
                        ['package/Index.ets', 'libs/libmadcore.so'], []):
            upper = self.archive('invalid-upper.har', entries)
            with self.assertRaises(ValueError):
                check(self.core, upper, self.beta, self.hap)
        for entries in (LIBS + ['other/' + LIBS[0]], LIBS[:1]):
            hap = self.archive('invalid.hap', entries)
            with self.assertRaisesRegex(ValueError, 'exactly one packaged copy'):
                check(self.core, self.alpha, self.beta, hap)

    def test_invalid_mode_and_no_sdk_runtime_in_core_har(self):
        with self.assertRaisesRegex(ValueError, 'Unknown HAR variant'):
            check(self.core, self.alpha, self.beta, self.hap, 'typo')
        contaminated = self.archive('contaminated.har', LIBS + [CXX], tar=True)
        with self.assertRaisesRegex(ValueError, 'must not bundle the test host C'):
            check(contaminated, self.alpha, self.beta, self.hap, 'default')


class ShellPreflight(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.checkout = root / 'checkout'
        self.script = self.checkout / 'tools/build_harmony_har.sh'
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(Path(__file__).with_name(self.script.name), self.script)
        native = self.checkout / 'madcore/build/bin/ohosArm64/releaseShared'
        native.mkdir(parents=True)
        for name in ('libmadcore.so', 'libmadcore_napi.so', 'libmadcore_copied_bridge.so'):
            (native / name).write_text('synthetic input; not an ELF')
        shims = root / 'shims'
        shims.mkdir()
        self.sentinel = root / 'curl-called'
        (shims / 'curl').write_text('#!/bin/sh\ntouch "$MADCORE_TEST_CURL"\nexit 97\n')
        (shims / 'readelf').write_text(
            '#!/bin/sh\ncase "$MADCORE_TEST_READELF" in\n'
            '  fail) exit 3 ;;\n'
            '  core) case "$3" in */libmadcore.so) echo mc_http_open;; esac ;;\n'
            '  napi) case "$3" in */libmadcore_napi.so) echo madcore_copied_http_test_poll;; esac ;;\n'
            '  clean) echo madcore_abi_version ;;\n'
            '  *) exit 3 ;;\nesac\n'
        )
        for shim in shims.iterdir():
            shim.chmod(0o700)
        self.env = dict(os.environ, PATH=f'{shims}:{os.environ["PATH"]}',
                        MADCORE_TEST_CURL=str(self.sentinel), RUNNER_TEMP=str(root))
        # A caller's shell startup or readelf override must not alter the shims.
        for key in ('BASH_ENV', 'ENV', 'READELF', 'MADCORE_COPIED_HTTP'):
            self.env.pop(key, None)

    def shell(self, mode, *args, reader='fail'):
        env = dict(self.env, MADCORE_TEST_READELF=reader)
        if mode is not None:
            env['MADCORE_COPIED_HTTP'] = mode
        return subprocess.run(['bash', str(self.script), *args], env=env, timeout=10,
                              check=False, capture_output=True, text=True)

    def test_variant_paths_and_bad_modes_are_offline(self):
        for mode, relative in [
            (None, 'build/harmony/madcore.har'), ('0', 'build/harmony/madcore.har'),
            ('1', 'build/harmony/experimental/madcore.har'),
        ]:
            result = self.shell(mode, '--print-output-path')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.checkout / relative))
        for mode in ('', 'experimental', '2'):
            result = self.shell(mode)
            self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.sentinel.exists())

    def test_experimental_symbols_and_unreadable_elf_stop_before_curl(self):
        for mode, diagnostic in [('core', 'Experimental symbols'),
                                 ('napi', 'Experimental symbols'),
                                 ('fail', 'Cannot check default native input symbols')]:
            with self.subTest(mode=mode):
                result = self.shell('0', reader=mode)
                self.assertEqual(result.returncode, 1)
                self.assertIn(diagnostic, result.stderr)
                self.assertFalse(self.sentinel.exists())

    def test_clean_default_does_not_require_or_inspect_stale_facade(self):
        result = self.shell('0', reader='clean')
        # This is the exit from our non-network curl stub, not a vendor tool.
        self.assertEqual(result.returncode, 97, result.stderr)
        self.assertTrue(self.sentinel.exists())


if __name__ == '__main__':
    unittest.main()
