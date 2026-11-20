"""Scratch-only Apple KLIB rehearsal: exact Core storage, two uppers, no release."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

from check_publication_graph import inspect
from rehearse_immutable_maven import (SNAPSHOT, JVM_EXCLUSIVE, JVM_MAVEN,
                                       canonical, repo_path, validate_internal_version, validate_version)

REVISION = '5145f4fbc15c401d1f6566c8c512821cc551bc43'
CORE = 'com.mad.core'
UPPERS = 'com.mad.composition'
UPPER_VERSION = '0.1.0'
TARGETS = {'iosarm64': 'ios_arm64', 'iossimulatorarm64': 'ios_simulator_arm64'}
PRODUCERS = 'examples/ios-kotlin-composition/producers/build.gradle'
UMBRELLA = 'examples/ios-kotlin-composition/umbrella/build.gradle'
PINS = {
    'build.gradle': ('0841ab8ca42a0e059a253c31cdce416b33105202', 1),
    'SDK-MODULES.json': ('c085a81db2a801eb7c522082ba0886a245ad7721', 1),
    PRODUCERS: ('630f37d5adfb9d0d49aed34f8367f2964d6f9466', 1),
    UMBRELLA: ('4d82c446635d970266b6b082dca6edb38aa59208', 2),
}

class EvidenceError(ValueError):
    """Keep diagnostic text private; use only a fixed code in automation."""
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


VERIFY_RESOLVED = b"""        def coreVersion = '@EXPECTED@'
        def exact = { id -> id instanceof org.gradle.api.artifacts.component.ModuleComponentIdentifier &&
            id.group in ['com.mad.core', 'com.mad.composition'] && id.module.contains('-ios') }
        def key = { id -> "${id.group}:${id.module}:${id.version}".toString() }
        def files = [:]
        def coreRepo = file(providers.gradleProperty('madcoreRepository').get())
        def upperRepo = file(providers.gradleProperty('upperRepository').get())
        def add = { repo, group, module, version ->
            files["${group}:${module}:${version}".toString()] =
                new File(repo, "${group.replace('.', '/')}/${module}/${version}/${module}-${version}.klib")
        }
        add(coreRepo, 'com.mad.core', 'core-storage-iossimulatorarm64', coreVersion)
        add(upperRepo, 'com.mad.composition', 'upper-alpha-iossimulatorarm64', '0.1.0')
        add(upperRepo, 'com.mad.composition', 'upper-beta-iossimulatorarm64', '0.1.0')
        def required = files.keySet().toList().sort()
        if (ids.findAll(exact).collect(key).sort() != required) {
            throw new GradleException('MADCORE_IOS_SELECTED_COORDINATES')
        }
        def selected = configuration.incoming.artifacts.artifacts.findAll { exact(it.id.componentIdentifier) }
        if (selected.collect { key(it.id.componentIdentifier) }.sort() != required) {
            throw new GradleException('MADCORE_IOS_SELECTED_ARTIFACTS')
        }
        selected.each { artifact ->
            def expected = files[key(artifact.id.componentIdentifier)]
            if (!expected.isFile() || !artifact.file.isFile() ||
                java.nio.file.Files.mismatch(expected.toPath(), artifact.file.toPath()) != -1L) {
                throw new GradleException('MADCORE_IOS_SELECTED_BYTES')
            }
        }
"""


def prepare(root, version):
    try:
        validate_version(version)
    except ValueError as error:
        raise EvidenceError('requested-version', str(error)) from error
    if root.is_symlink() or any((root / name).exists() for name in ('.git', 'build')):
        raise EvidenceError('source-layout', 'expected fresh archive scratch, not a live checkout')
    changes = {}
    for name, (expected, pins) in PINS.items():
        path = root / name
        if path.is_symlink() or path.resolve() != root.resolve() / name:
            raise EvidenceError('source-layout', f'unexpected source path: {name}')
        data = path.read_bytes()
        digest = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
        if digest != expected or data.count(SNAPSHOT) != pins:
            raise EvidenceError('source-drift', f'pinned source drift or repeated overlay: {name}')
        result = data.replace(SNAPSHOT, version.encode())
        if name in (PRODUCERS, UMBRELLA):
            indent = b'    ' if name == PRODUCERS else b''
            before = indent + JVM_MAVEN
            after = b'\n'.join(indent + line for line in JVM_EXCLUSIVE.splitlines())
            if result.count(before) != 1:
                raise EvidenceError('source-drift', 'pinned iOS staged repository line changed')
            result = result.replace(before, after)
        if name == PRODUCERS:
            result = result.replace(b'        iosSimulatorArm64()', b'        iosArm64()\n        iosSimulatorArm64()')
        if name == UMBRELLA:
            upper = JVM_EXCLUSIVE.replace(b'madcoreRepository', b'upperRepository').replace(
                b'com.mad.core', UPPERS.encode())
            old_upper = JVM_MAVEN.replace(b'madcoreRepository', b'upperRepository')
            result = result.replace(old_upper, upper)
            start = result.index(b"        ['upper-alpha-iossimulatorarm64'")
            end = result.index(b'        println(', start)
            result = result[:start] + VERIFY_RESOLVED.replace(b'@EXPECTED@', version.encode()) + result[end:]
        changes[path] = result
    for path, data in changes.items():
        path.write_bytes(data)


def staged_path(repo, metadata, url, code):
    try:
        return repo_path(repo, metadata, url)
    except ValueError as error:
        raise EvidenceError(code, str(error)) from error


def xml_coordinates(path):
    tree = ET.parse(path).getroot()
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    def g(name):
        return tuple(name.findtext('m:' + key, namespaces=ns) for key in ('groupId', 'artifactId', 'version'))
    return g(tree), [g(dep) for dep in tree.findall('m:dependencies/m:dependency', ns)]


def klib_target(path, expected):
    with zipfile.ZipFile(path) as library:
        manifests = [item for item in library.infolist()
                     if len(Path(item.filename).parts) == 2 and Path(item.filename).name == 'manifest']
        if len(manifests) != 1 or manifests[0].file_size > 64 * 1024:
            raise EvidenceError('klib-manifest', f'expected a single small native KLIB manifest: {path.name}')
        data = library.read(manifests[0]).decode('iso-8859-1')
    for name, value in (('builtins_platform', 'NATIVE'), ('native_targets', expected)):
        rows = [line.split('=', 1)[1] for line in data.splitlines() if line.startswith(name + '=')]
        if rows != [value]:
            raise EvidenceError('klib-target', f'wrong actual KLIB target or platform: {path.name}')


def verify(repo, version, upper=False):
    try:
        validate_version(version)
    except ValueError as error:
        raise EvidenceError('requested-version', str(error)) from error
    if not repo.is_dir() or repo.is_symlink() or any(p.is_symlink() for p in repo.rglob('*')):
        raise EvidenceError('stage-layout', 'not an isolated regular stage')
    repo = repo.resolve()
    group = UPPERS if upper else CORE
    pinned = UPPER_VERSION if upper else version
    roots = ('upper-alpha', 'upper-beta') if upper else ('core-storage',)
    suffixes = (*TARGETS,) if upper else ('jvm', *TARGETS)
    paths = {canonical(repo, group, root + (f'-{suffix}' if suffix else ''), pinned): (root, suffix)
             for root in roots for suffix in ('', *suffixes)}
    if set(paths) != set(repo.rglob('*.module')) or {p.with_suffix('.pom') for p in paths} != set(repo.rglob('*.pom')):
        raise EvidenceError('metadata-layout', 'missing, stale or unexpected staged metadata coordinates')
    if any(path.parent.name == pinned for path in repo.rglob('maven-metadata.xml')):
        raise EvidenceError('metadata-layout', 'unexpected version-directory metadata')
    expected_klibs = set()
    core_module = 'core-storage'
    for path, (root, suffix) in sorted(paths.items()):
        artifact = root + (f'-{suffix}' if suffix else '')
        allowed_core = {core_module, f'{core_module}-{suffix}'} if suffix else {core_module}
        pom, pom_deps = xml_coordinates(path.with_suffix('.pom'))
        if pom != (group, artifact, pinned):
            raise EvidenceError('pom-coordinates', 'staged POM identity mismatch')
        if upper:
            edges = [(name, ver) for g, name, ver in pom_deps if g == CORE]
            if len(edges) != 1 or edges[0][0] not in allowed_core or edges[0][1] != version:
                raise EvidenceError('pom-core-edge', 'upper POM must request exactly one expected Core storage coordinate')
        module = json.loads(path.read_text(encoding='utf-8'))
        component = module['component']
        if module['formatVersion'] != '1.1' or (component['group'], component['version']) != (group, pinned):
            raise EvidenceError('gmm-coordinates', 'staged module identity mismatch')
        if 'url' in component:
            if (not suffix or component['module'] != root or staged_path(repo, path, component['url'], 'gmm-redirect')
                    != canonical(repo, group, root, pinned)):
                raise EvidenceError('gmm-redirect', 'staged component must link its own root')
        elif component['module'] != artifact:
            raise EvidenceError('gmm-coordinates', 'staged component artifact mismatch')
        wanted = {f'{root}-{target}' for target in suffixes} if not suffix else set()
        selected = set()
        found_core = False
        native = set()
        local = set()
        for variant in module['variants']:
            if 'available-at' in variant:
                ref = variant['available-at']
                target = ref['module']
                if (target not in wanted or (ref['group'], ref['version']) != (group, pinned) or
                        staged_path(repo, path, ref['url'], 'gmm-redirect') != canonical(repo, group, target, pinned)):
                    raise EvidenceError('gmm-redirect', 'staged target redirect is stale or points away from its own target')
                selected.add(target)
            for key in ('dependencies', 'dependencyConstraints'):
                for entry in variant.get(key, ()):
                    if entry['group'] == CORE:
                        try:
                            validate_internal_version(entry, version)
                        except ValueError as error:
                            raise EvidenceError('gmm-core-edge', str(error)) from error
                        if entry['module'] not in allowed_core:
                            raise EvidenceError('gmm-core-edge', 'unexpected Core module in storage composition')
                        found_core |= key == 'dependencies'
            for item in variant.get('files', ()):
                file = staged_path(repo, path, item['url'], 'artifact-layout')
                if (file.parent != path.parent or file.name != item['url']
                        or file.stat().st_size != item['size']):
                    raise EvidenceError('artifact-layout', 'staged file path or size mismatch')
                with file.open('rb') as stream:
                    if hashlib.file_digest(stream, 'sha256').hexdigest() != item['sha256']:
                        raise EvidenceError('artifact-checksum', 'staged file checksum mismatch')
                local.add(file.name)
                if file.suffix == '.klib':
                    if suffix not in TARGETS or file.name != f'{artifact}-{pinned}.klib':
                        raise EvidenceError('klib-layout', 'unexpected native platform artifact')
                    klib_target(file, TARGETS[suffix])
                    native.add(file)
        if selected != wanted:
            raise EvidenceError('gmm-target-set', 'staged target is missing')
        if upper and not found_core:
            raise EvidenceError('gmm-core-edge', 'upper Core dependency is missing')
        if suffix in TARGETS and len(native) != 1:
            raise EvidenceError('klib-layout', 'missing expected native artifact')
        if suffix not in TARGETS and f'{artifact}-{pinned}.jar' not in local:
            raise EvidenceError('artifact-layout', 'missing root or JVM metadata artifact')
        expected_klibs.update(native)
    if set(repo.rglob('*.klib')) != expected_klibs:
        raise EvidenceError('klib-layout', 'unexpected staged native KLIB file')
    return len(expected_klibs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('prepare', 'verify-core', 'verify-uppers'))
    parser.add_argument('path', type=Path)
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    try:
        if args.mode == 'prepare' and args.manifest is None:
            prepare(args.path, args.expected_version)
            print(f'iOS storage rehearsal prepared from exact {REVISION[:8]}; no build')
            return
        if args.mode == 'verify-core' and args.manifest:
            manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
            if manifest['version'] != args.expected_version or 'core-storage' not in manifest['production']:
                raise EvidenceError('manifest-version', 'scratch manifest disagrees with expected exact storage version')
            count = verify(args.path, args.expected_version)
            subset = dict(manifest, umbrella='core-storage', production=[], optInTestOnly=[])
            try:
                inspect(args.path.resolve(), subset)
            except (ValueError, ET.ParseError) as error:
                raise EvidenceError('pom-graph', str(error)) from error
        elif args.mode == 'verify-uppers' and not args.manifest:
            count = verify(args.path, args.expected_version, upper=True)
        else:
            raise EvidenceError('arguments', 'invalid iOS verification mode arguments')
        print(f'iOS {args.mode}: {count} exact device/simulator KLIBs; no binary executed')
    except EvidenceError as error:
        sys.exit(f'MADCORE_IOS_REASON={error.code}')
    except zipfile.BadZipFile:
        sys.exit('MADCORE_IOS_REASON=klib-zip')
    except (json.JSONDecodeError, ET.ParseError, KeyError, TypeError):
        sys.exit('MADCORE_IOS_REASON=metadata-invalid')
    except OSError:
        sys.exit('MADCORE_IOS_REASON=file-read')
    except ValueError:
        sys.exit('MADCORE_IOS_REASON=metadata-or-file-layout')


if __name__ == '__main__':
    main()
