"""Host-only tests; no Gradle/native build or repository publishing."""
import hashlib
import json
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory
import unittest

from rehearse_immutable_maven import PINS, prepare, validate_version, verify, verify_android_uppers


EXPECTED = '0.0.0-rehearsal.1'  # Synthetic test input, not a proposed release.
ROOT = Path(__file__).resolve().parents[1]
CORE = 'com.mad.core'
UPPER = 'example.madcore.upper'


def fixture(repo, group, name, version, *, payload='.jar', targets=(), parent=None, dep=None):
    stem = name + '-' + version
    folder = repo / group.replace('.', '/') / name / version
    folder.mkdir(parents=True)
    artifact = folder / (stem + payload)
    artifact.write_bytes(b'test-only byte payload')
    component = dict(group=group, module=parent or name, version=version)
    if parent:
        component['url'] = f'../../{parent}/{version}/{parent}-{version}.module'
    attrs = dict(name='api', files=[dict(name=artifact.name, url=artifact.name, size=artifact.stat().st_size,
                                        sha256=hashlib.sha256(artifact.read_bytes()).hexdigest())])
    variants = [attrs]
    for target in targets:
        variants.append(dict(name=target, **{'available-at': dict(group=group, module=target, version=version,
                            url=f'../../{target}/{version}/{target}-{version}.module')}))
    if dep:
        attrs['dependencies'] = [dict(group=dep[0], module=dep[1], version=dict(requires=dep[2]))]
    path = folder / (stem + '.module')
    save(path, dict(formatVersion='1.1', component=component, variants=variants))
    dependency = '' if dep is None else (
        f'<dependencies><dependency><groupId>{dep[0]}</groupId><artifactId>{dep[1]}</artifactId>'
        f'<version>{dep[2]}</version></dependency></dependencies>'
    )
    path.with_suffix('.pom').write_text(
        f'<project xmlns="http://maven.apache.org/POM/4.0.0"><groupId>{group}</groupId>'
        f'<artifactId>{name}</artifactId><version>{version}</version>{dependency}</project>'
    )
    return path


def save(path, data):
    path.write_text(json.dumps(data))


class RehearsalTest(unittest.TestCase):
    def test_exact_overlay_and_refuse_drift(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in PINS:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
            app = root / 'examples/android-consumer/app/build.gradle'
            manifest = root / 'SDK-MODULES.json'
            before = manifest.read_bytes()
            original = app.read_bytes()
            app.write_bytes(original + b'\n// drift')
            with self.assertRaisesRegex(ValueError, 'drift'):
                prepare(root, EXPECTED)
            self.assertEqual(manifest.read_bytes(), before)
            app.write_bytes(original)
            prepare(root, EXPECTED)
            self.assertIn(EXPECTED.encode(), manifest.read_bytes())
            self.assertEqual(app.read_bytes(), original.replace(b'0.1.0-SNAPSHOT', EXPECTED.encode()))
            for name in PINS:
                if name.startswith('examples/jvm-consumer/'):
                    self.assertIn('exclusiveContent', (root / name).read_text())
            with self.assertRaisesRegex(ValueError, 'repeated overlay'):
                prepare(root, EXPECTED)
            (root / 'build').mkdir()
            with self.assertRaisesRegex(ValueError, 'fresh git archive'):
                prepare(root, EXPECTED)
        for value in ('0.1.0', '0.1.0-SNAPSHOT', '1.+', '1.0.0-rehearsal.0', '1.0.0-rehearsal.１'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_version(value)

    def test_real_layout_expected_version_and_negative_metadata(self):
        manifest = dict(group=CORE, version=EXPECTED, production=[], optInTestOnly=[], umbrella='sdk',
                        allowedExternal=[])
        for lane in ('jvm', 'android'):
            for mode in ('ok', 'manifest', 'missing', 'checksum', 'internal', 'redirect',
                         'wrong-group', 'snapshot-metadata', 'omitted-target', 'bad-name', 'bad-file-url',
                         'root-redirect', 'target-direct'):
                with self.subTest(lane=lane, mode=mode), TemporaryDirectory() as tmp:
                    base = Path(tmp)
                    repo = base / 'staging'
                    targets = ('sdk-jvm', 'sdk-android') if lane == 'android' else ('sdk-jvm',)
                    module = fixture(repo, CORE, 'sdk', EXPECTED, targets=targets)
                    jvm = fixture(repo, CORE, 'sdk-jvm', EXPECTED, parent='sdk')
                    if lane == 'android':
                        fixture(repo, CORE, 'sdk-android', EXPECTED, parent='sdk', payload='.aar')
                    if mode == 'ok':
                        doc = json.loads(module.read_text())
                        doc['variants'][0]['files'][0]['name'] = f'sdk-metadata-{EXPECTED}.jar'
                        save(module, doc)
                        if lane == 'android':
                            android = next(repo.rglob(f'sdk-android-{EXPECTED}.module'))
                            doc = json.loads(android.read_text())
                            doc['variants'][0]['files'][0]['name'] = 'sdk-release.aar'
                            save(android, doc)
                        # Immutable repository metadata one level above the version is legitimate.
                        (module.parent.parent / 'maven-metadata.xml').write_text('<metadata/>')
                        count = 3 if lane == 'android' else 2
                        self.assertEqual(verify(repo, manifest, lane, EXPECTED), (count, count))
                        continue
                    doc = json.loads(module.read_text())
                    if mode == 'missing':
                        jvm.unlink()
                    elif mode == 'checksum':
                        module.with_suffix('.jar').write_bytes(b'stale byte payload!!!')
                    elif mode == 'internal':
                        doc['variants'][0]['dependencies'] = [dict(group=CORE, module='sdk',
                                                                   version=dict(requires='0.1.0-SNAPSHOT'))]
                    elif mode == 'redirect':
                        decoy = fixture(base / 'decoy', CORE, 'sdk-jvm', EXPECTED)
                        relative = Path(*(['..'] * len(module.parent.relative_to(base).parts))) / decoy.relative_to(base)
                        doc['variants'][1]['available-at']['url'] = relative.as_posix()
                    elif mode == 'wrong-group':
                        doc['component']['group'] = 'wrong.group'
                    elif mode == 'snapshot-metadata':
                        (module.parent / 'maven-metadata.xml').write_text('<metadata/>')
                    elif mode == 'omitted-target':
                        doc['variants'].pop()
                    elif mode == 'bad-name':
                        doc['variants'][0]['files'][0]['name'] = f'sdk-kotlin-{EXPECTED}-sources.jar'
                    elif mode == 'bad-file-url':
                        doc['variants'][0]['files'][0]['url'] = './' + doc['variants'][0]['files'][0]['url']
                    elif mode == 'root-redirect':
                        doc['component']['url'] = module.name
                    elif mode == 'target-direct':
                        data = json.loads(jvm.read_text())
                        data['component'].pop('url')
                        data['component']['module'] = 'sdk-jvm'
                        save(jvm, data)
                        count = 3 if lane == 'android' else 2
                        self.assertEqual(verify(repo, manifest, lane, EXPECTED), (count, count))
                        continue
                    save(module, doc)
                    with self.assertRaises(ValueError):
                        verify(repo, {**manifest, 'version': '0.1.0-SNAPSHOT'} if mode == 'manifest' else manifest,
                               lane, EXPECTED)

    def test_existing_same_group_sibling_cannot_replace_own_target_or_root(self):
        manifest = dict(group=CORE, version=EXPECTED, production=['base'], optInTestOnly=[], umbrella='sdk',
                        allowedExternal=[])
        for mode in ('wrong-target', 'wrong-parent', 'wrong-direct-component', 'wrong-logical-module'):
            with self.subTest(mode=mode), TemporaryDirectory() as tmp:
                repo = Path(tmp)
                fixture(repo, CORE, 'base', EXPECTED, targets=('base-jvm',))
                fixture(repo, CORE, 'base-jvm', EXPECTED, parent='base')
                umbrella = fixture(repo, CORE, 'sdk', EXPECTED, targets=('sdk-jvm',),
                                   dep=(CORE, 'base', EXPECTED))
                target = fixture(repo, CORE, 'sdk-jvm', EXPECTED, parent='sdk',
                                 dep=(CORE, 'base-jvm', EXPECTED))
                self.assertEqual(verify(repo, manifest, 'jvm', EXPECTED), (4, 4))
                path = umbrella if mode == 'wrong-target' else target
                data = json.loads(path.read_text())
                if mode == 'wrong-target':
                    redirect = data['variants'][1]['available-at']
                    redirect.update(module='base-jvm', url=f'../../base-jvm/{EXPECTED}/base-jvm-{EXPECTED}.module')
                elif mode == 'wrong-parent':
                    data['component'].update(module='base', url=f'../../base/{EXPECTED}/base-{EXPECTED}.module')
                elif mode == 'wrong-direct-component':
                    data['component'].pop('url')
                    data['component']['module'] = 'base-jvm'
                else:
                    data['variants'][0]['files'][0]['name'] = f'base-jvm-{EXPECTED}.jar'
                save(path, data)
                with self.assertRaises(ValueError):
                    verify(repo, manifest, 'jvm', EXPECTED)

    def test_android_upper_dependency_requires_exact_core_version(self):
        with TemporaryDirectory() as tmp:
            repo = Path(tmp)
            for name in ('alpha', 'beta'):
                fixture(repo, UPPER, name, '0.1.0', payload='.aar', dep=(CORE, 'madcore', EXPECTED))
            verify_android_uppers(repo, EXPECTED)
            beta = next(repo.rglob('beta-0.1.0.module'))
            bad = json.loads(beta.read_text())
            bad['variants'][0]['dependencies'][0]['version']['requires'] = '0.1.0-SNAPSHOT'
            save(beta, bad)
            with self.assertRaisesRegex(ValueError, 'stale'):
                verify_android_uppers(repo, EXPECTED)


if __name__ == '__main__':
    unittest.main()
