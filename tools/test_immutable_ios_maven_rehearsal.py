"""Synthetic layout, version, link provenance, and native identity tests."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
import zipfile

from rehearse_immutable_ios_maven import (CORE, PINS, PRODUCERS, TARGETS, UMBRELLA, UPPERS,
                                          UPPER_VERSION, prepare, verify)

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.0.0-rehearsal.1'  # Test fixture, not a release choice.


def save(path, metadata):
    path.write_text(json.dumps(metadata), encoding='utf-8')


def native(path, target):
    with zipfile.ZipFile(path, 'w') as artifact:
        artifact.writestr('default/manifest',
                          f'builtins_platform=NATIVE\nnative_targets={target}\nunique_name=test-only\n')
        artifact.writestr('default/ir/files.knf', 'synthetic body')


def file_info(path):
    return dict(name=path.name, url=path.name, size=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def fixture(repo, *, upper=False):
    group, version = (UPPERS, UPPER_VERSION) if upper else (CORE, VERSION)
    roots = ('upper-alpha', 'upper-beta') if upper else ('core-storage',)
    targets = tuple(TARGETS) if upper else ('jvm', *TARGETS)
    result = {}
    for root in roots:
        for suffix in ('', *targets):
            artifact = root + (f'-{suffix}' if suffix else '')
            parent = repo / group.replace('.', '/') / artifact / version
            parent.mkdir(parents=True)
            name = f'{artifact}-{version}'
            file = parent / (name + ('.klib' if suffix in TARGETS else '.jar'))
            if suffix in TARGETS:
                native(file, TARGETS[suffix])
            else:
                file.write_bytes(b'synthetic metadata or JVM jar bytes')
            with_file = dict(name='localApi', files=[file_info(file)])
            dependency = ''
            if upper:
                with_file['dependencies'] = [dict(group=CORE, module='core-storage', version={'requires': VERSION})]
                dependency = ('<dependencies><dependency><groupId>com.mad.core</groupId>'
                              f'<artifactId>core-storage</artifactId><version>{VERSION}</version>'
                              '</dependency></dependencies>')
            variants = [with_file]
            component = dict(group=group, module=artifact, version=version)
            if suffix:
                component.update(module=root, url=f'../../{root}/{version}/{root}-{version}.module')
            else:
                for target in targets:
                    name_suffix = f'{root}-{target}'
                    variants.append({'name': target, 'available-at': dict(
                        group=group, module=name_suffix, version=version,
                        url=f'../../{name_suffix}/{version}/{name_suffix}-{version}.module')})
            path = parent / (name + '.module')
            save(path, dict(formatVersion='1.1', component=component, variants=variants))
            pom = ('<project xmlns="http://maven.apache.org/POM/4.0.0">'
                   f'<groupId>{group}</groupId><artifactId>{artifact}</artifactId>'
                   f'<version>{version}</version>{dependency}</project>')
            path.with_suffix('.pom').write_text(pom, encoding='utf-8')
            result[artifact] = path
    return result


class IOSRehearsal(unittest.TestCase):
    def test_exact_source_overlay_and_independent_resolution_assertions(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in PINS:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, root / path)
            producer = root / PRODUCERS
            original = producer.read_bytes()
            producer.write_bytes(original + b'# stale')
            with self.assertRaisesRegex(ValueError, 'drift'):
                prepare(root, VERSION)
            self.assertIn('0.1.0-SNAPSHOT', (root / UMBRELLA).read_text())
            producer.write_bytes(original)
            prepare(root, VERSION)
            self.assertIn('iosArm64()', producer.read_text())
            self.assertIn('iosSimulatorArm64()', producer.read_text())
            umbrella = (root / UMBRELLA).read_text()
            self.assertEqual(umbrella.count('exclusiveContent'), 2)
            self.assertIn('Files.mismatch(expected.toPath(), artifact.file.toPath())', umbrella)
            self.assertIn('${module}-${version}.klib', umbrella)
            self.assertIn(f"def coreVersion = '{VERSION}'", umbrella)
            self.assertNotIn('0.1.0-SNAPSHOT', umbrella)
            with self.assertRaisesRegex(ValueError, 'repeated'):
                prepare(root, VERSION)

    def test_core_both_targets_and_klib_bytes(self):
        for mode in ('good', 'omitted-target', 'wrong-target-contents', 'wrong-checksum', 'stale-link',
                     'wrong-platform-backlink', 'extra-klib'):
            with self.subTest(mode=mode), TemporaryDirectory() as tmp:
                repo = Path(tmp)
                files = fixture(repo)
                main = files['core-storage']
                target = files['core-storage-iosarm64']
                if mode == 'good':
                    self.assertEqual(verify(repo, VERSION), 2)
                    continue
                if mode in ('omitted-target', 'stale-link'):
                    row = json.loads(main.read_text())
                    if mode == 'omitted-target':
                        row['variants'].pop()
                    else:
                        row['variants'][1]['available-at']['version'] = '0.1.0-SNAPSHOT'
                    save(main, row)
                elif mode in ('wrong-target-contents', 'wrong-checksum'):
                    klib = target.with_suffix('.klib')
                    native(klib, 'ios_simulator_arm64')
                    if mode == 'wrong-target-contents':
                        row = json.loads(target.read_text())
                        row['variants'][0]['files'][0] = file_info(klib)
                        save(target, row)
                elif mode == 'wrong-platform-backlink':
                    row = json.loads(target.read_text())
                    row['component']['url'] = target.name
                    save(target, row)
                else:
                    (repo / 'extra.klib').touch()
                with self.assertRaises(ValueError):
                    verify(repo, VERSION)

    def test_cli_uses_fixed_reasons_without_metadata_or_paths(self):
        for mode, code in (('missing-target', 'gmm-target-set'), ('decoy', 'gmm-redirect'),
                           ('bad-json', 'metadata-invalid'), ('stale', 'gmm-core-edge'),
                           ('bad-checksum', 'artifact-checksum'), ('bad-zip', 'klib-zip')):
            with self.subTest(mode=mode), TemporaryDirectory(prefix='private-do-not-echo-') as tmp:
                repo = Path(tmp)
                files = fixture(repo, upper=True)
                if mode == 'bad-json':
                    files['upper-alpha'].write_text('private metadata, not JSON')
                elif mode in ('bad-checksum', 'bad-zip'):
                    target = files['upper-alpha-iosarm64']
                    binary = target.with_suffix('.klib')
                    binary.write_bytes(b'synthetic invalid archive')
                    data = json.loads(target.read_text())
                    info = file_info(binary)
                    if mode == 'bad-checksum':
                        info['sha256'] = '0' * 64
                    data['variants'][0]['files'][0] = info
                    save(target, data)
                else:
                    root = files['upper-alpha']
                    data = json.loads(root.read_text())
                    if mode == 'missing-target':
                        data['variants'].pop()
                    elif mode == 'decoy':
                        data['variants'][1]['available-at']['url'] = '../../../../private.module'
                    else:
                        data['variants'][0]['dependencies'][0]['version']['requires'] = '0.1.0-SNAPSHOT'
                    save(root, data)
                result = subprocess.run(
                    [sys.executable, '-B', str(ROOT / 'tools/rehearse_immutable_ios_maven.py'),
                     'verify-uppers', str(repo), '--expected-version', VERSION],
                    text=True, capture_output=True, check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertEqual(result.stderr, f'MADCORE_IOS_REASON={code}\n')

    def test_two_uppers_cannot_reference_same_group_decoy_or_snapshot(self):
        for mode in ('good', 'wrong-sibling', 'wrong-version', 'stale-pom', 'missing'):
            with self.subTest(mode=mode), TemporaryDirectory() as tmp:
                repo = Path(tmp)
                files = fixture(repo, upper=True)
                if mode == 'good':
                    self.assertEqual(verify(repo, VERSION, upper=True), 4)
                    continue
                path = files['upper-alpha']
                row = json.loads(path.read_text())
                if mode == 'wrong-sibling':
                    decoy = files['upper-beta-iosarm64']
                    row['variants'][1]['available-at'].update(
                        module='upper-beta-iosarm64',
                        url=f'../../upper-beta-iosarm64/{UPPER_VERSION}/{decoy.name}')
                elif mode == 'wrong-version':
                    row['variants'][0]['dependencies'][0]['version']['requires'] = '0.1.0-SNAPSHOT'
                elif mode == 'stale-pom':
                    pom = path.with_suffix('.pom')
                    pom.write_text(pom.read_text().replace(VERSION, '0.1.0-SNAPSHOT'))
                else:
                    files['upper-alpha-iosarm64'].unlink()
                save(path, row)
                with self.assertRaises(ValueError):
                    verify(repo, VERSION, upper=True)


if __name__ == '__main__':
    unittest.main()
