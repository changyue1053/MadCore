"""Synthetic output shapes only: not generated Kotlin or Swift ABI proof."""
import json
from pathlib import Path
import tempfile
import unittest

from check_abi_candidate_inventory import verify


class Inventory(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / 'SDK-MODULES.json').write_text(json.dumps({
            'production': ['core-config'], 'umbrella': 'madcore',
            'optInTestOnly': ['core-testkit'],
        }))

    def put(self, relative, data='synthetic ABI text\n'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    def seed(self, lane, kind):
        for module in ('core-config', 'madcore'):
            folder = (f'{module}/build/api-baseline/{lane}' if kind == 'actual'
                      else f'api-baseline/{lane}/{module}')
            if lane == 'android':
                self.put(f'{folder}/android/{module}.api')
                self.put(f'{folder}/jvm/{module}.api')
            else:
                self.put(f'{folder}/{module}.api')
            if lane == 'ios':
                self.put(f'{folder}/{module}.klib.api',
                         '// Klib ABI Dump\n// Targets: [iosArm64, iosSimulatorArm64]\n')

    def test_each_target_both_layouts(self):
        for lane in ('jvm', 'android', 'ios'):
            for kind in ('actual', 'reference'):
                with self.subTest(lane=lane, kind=kind):
                    self.seed(lane, kind)
                    verify(self.root, lane, kind)

    def test_jvm_is_not_android(self):
        self.seed('jvm', 'actual')
        with self.assertRaisesRegex(ValueError, 'missing'):
            verify(self.root, 'android', 'actual')

    def test_empty_and_missing_are_not_baselines(self):
        self.seed('jvm', 'reference')
        path = self.put('api-baseline/jvm/madcore/madcore.api', '\n')
        with self.assertRaisesRegex(ValueError, 'Empty'):
            verify(self.root, 'jvm', 'reference')
        path.unlink()
        with self.assertRaisesRegex(ValueError, 'missing'):
            verify(self.root, 'jvm', 'reference')

    def test_ios_missing_one_target_is_rejected(self):
        self.seed('ios', 'actual')
        self.put('core-config/build/api-baseline/ios/core-config.klib.api',
                 '// Klib ABI Dump\n// Targets: [iosArm64]\n')
        with self.assertRaisesRegex(ValueError, 'both real iOS targets'):
            verify(self.root, 'ios', 'actual')

    def test_extra_reference_dump_and_module_are_rejected(self):
        self.seed('android', 'reference')
        extra = self.put('api-baseline/android/core-config/stale.api')
        with self.assertRaisesRegex(ValueError, 'extra'):
            verify(self.root, 'android', 'reference')
        extra.unlink()
        self.put('api-baseline/android/core-testkit/core-testkit.api')
        with self.assertRaisesRegex(ValueError, 'Unexpected reference modules'):
            verify(self.root, 'android', 'reference')


if __name__ == '__main__':
    unittest.main()
