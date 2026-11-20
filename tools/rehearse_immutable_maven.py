"""Locked local-only JVM/Android version rehearsal; no release or iOS claim."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

from check_publication_graph import inspect

REVISION = '66a4789c14c1e9dfd5d3c7118ca90effc8c4e8b7'
SNAPSHOT = b'0.1.0-SNAPSHOT'
PINS = {
    'build.gradle': ('0841ab8ca42a0e059a253c31cdce416b33105202', 1),
    'SDK-MODULES.json': ('c085a81db2a801eb7c522082ba0886a245ad7721', 1),
    'examples/android-upper-sdks/alpha/build.gradle': ('e0a9499fbfc3645bb30560a593ec8d0909ab4260', 1),
    'examples/android-upper-sdks/beta/build.gradle': ('ab5426f5118b569155c2d20222dcc86f57bdc98a', 1),
    'examples/android-consumer/app/build.gradle': ('75c094b3f760c9e210aad0385e903cab4a0f0d96', 1),
    'examples/jvm-consumer/build.gradle': ('853d05891b0d22f37f5acbbf2577bf54a1a6c69c', 3),
    'examples/jvm-consumer/upper-alpha/build.gradle': ('0d6931676f3422eb2bbc1e12ae1d89ca7e99a650', 1),
    'examples/jvm-consumer/upper-beta/build.gradle': ('0d6931676f3422eb2bbc1e12ae1d89ca7e99a650', 1),
}
JVM_FILES = {name for name in PINS if name.startswith('examples/jvm-consumer/')}
JVM_MAVEN = b"    maven { url = uri(providers.gradleProperty('madcoreRepository').get()) }"
JVM_EXCLUSIVE = b"""    exclusiveContent {
        forRepository { maven { url = uri(providers.gradleProperty('madcoreRepository').get()) } }
        filter { includeGroup('com.mad.core') }
    }"""


def validate_version(version):
    if not re.fullmatch(r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)-rehearsal\.[1-9]\d*',
                        version, flags=re.ASCII) or len(version) > 64:
        raise ValueError('expected explicit X.Y.Z-rehearsal.N token, not a release, range or snapshot')


def prepare(root, version):
    validate_version(version)
    if root.is_symlink() or any((root / name).exists() for name in ('.git', 'build')):
        raise ValueError('expected a fresh git archive scratch tree, not a checkout or reused build')
    # Confirm every expected original before changing any bytes.
    changes = {}
    for name, (expected_blob, count) in PINS.items():
        path = root / name
        if path.is_symlink() or path.resolve() != root.resolve() / name:
            raise ValueError(f'unexpected source path: {name}')
        data = path.read_bytes()
        blob = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest()
        if blob != expected_blob or data.count(SNAPSHOT) != count:
            raise ValueError(f'baseline drift or repeated overlay: {name}')
        updated = data.replace(SNAPSHOT, version.encode())
        if name in JVM_FILES:
            if updated.count(JVM_MAVEN) != 1:
                raise ValueError(f'expected one staged JVM Maven repository: {name}')
            updated = updated.replace(JVM_MAVEN, JVM_EXCLUSIVE)
        changes[path] = updated
    for path, updated in changes.items():
        path.write_bytes(updated)


def json_file(path):
    return json.loads(path.read_text(encoding='utf-8'))


def repo_path(repo, current, raw_url):
    url = urlsplit(raw_url)
    if (url.scheme or url.netloc or url.query or url.fragment or url.path.startswith('/')
            or '%' in url.path or '\\' in url.path or not url.path):
        raise ValueError('expected a local, relative Gradle metadata URL')
    path = (current.parent / url.path).resolve()
    if not path.is_relative_to(repo) or not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'missing or out-of-stage metadata target: {current.name}')
    return path


def canonical(repo, group, module, version):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', module):
        raise ValueError('invalid metadata module name')
    return repo / group.replace('.', '/') / module / version / f'{module}-{version}.module'


def validate_internal_version(entry, version):
    rule = entry.get('version')
    if not isinstance(rule, dict) or not ({'requires', 'strictly'} & rule.keys()):
        raise ValueError('missing exact Gradle internal dependency version')
    if rule.keys() - {'requires', 'strictly', 'prefers'} or any(v != version for v in rule.values()):
        raise ValueError('stale, dynamic or rejected Gradle internal dependency version')


def validate_file_name(entry, file, artifact, root_artifact, version):
    # KGP publishes with the original basename as 'name'. Only the Maven
    # location ('url') is guaranteed to carry the canonical coordinates.
    match = re.fullmatch(
        re.escape(f'{artifact}-{version}') + r'(-[A-Za-z0-9][A-Za-z0-9_.-]*)?\.(jar|aar|json)',
        file.name,
    )
    if not match or entry['url'] != file.name:
        raise ValueError(f'noncanonical staged Gradle artifact filename: {file.name}')
    classifier, extension = match[1] or '', match[2]
    aliases = {file.name}
    if root_artifact is not None:
        stems = {artifact, root_artifact}
        if artifact == root_artifact:
            if not classifier and extension == 'jar':
                stems.add(f'{root_artifact}-metadata')
            if classifier == '-sources' and extension == 'jar':
                stems.add(f'{root_artifact}-kotlin')
            if classifier == '-kotlin-tooling-metadata' and extension == 'json':
                aliases.add('kotlin-tooling-metadata.json')
        if artifact == f'{root_artifact}-android':
            stems.update((f'{root_artifact}-release', f'{artifact}-release'))
            if classifier == '-lint' and extension == 'jar':
                aliases.add('lint.jar')
        aliases.update(f'{stem}{stamp}{classifier}.{extension}'
                       for stem in stems for stamp in ('', '-' + version))
    if entry['name'] not in aliases:
        raise ValueError(f'Gradle logical artifact name does not match its module or role: {file.name}')


def inspect_module(repo, path, group, version, artifact, *, root_artifact=None, expected_targets=(),
                   dependency_group=None, dependency_version=None):
    document = json_file(path)
    component = document['component']
    if document['formatVersion'] != '1.1' or component['group'] != group or component['version'] != version:
        raise ValueError(f'wrong Gradle component identity: {path.name}')
    if 'url' in component:
        target = repo_path(repo, path, component['url'])
        if (root_artifact is None or root_artifact == artifact or component['module'] != root_artifact
                or target != canonical(repo, group, root_artifact, version)):
            raise ValueError('Gradle component URL must point to its own multiplatform root')
    elif component['module'] != artifact:
        raise ValueError('wrong Gradle component artifact')
    found_dependency = False
    seen_files = set()
    seen_targets = set()
    logical_names = {}
    variants = document['variants']
    if not variants:
        raise ValueError(f'empty Gradle metadata variants: {path.name}')
    for variant in variants:
        for key in ('dependencies', 'dependencyConstraints'):
            for entry in variant.get(key, ()):
                if entry['group'] == (dependency_group or group):
                    validate_internal_version(entry, dependency_version or version)
                    if dependency_group and entry['module'] not in ('madcore', 'madcore-android'):
                        raise ValueError('unexpected Android upper Core dependency')
                    found_dependency |= key == 'dependencies'
        if 'available-at' in variant:
            location = variant['available-at']
            module = location['module']
            if (module not in expected_targets or location['group'] != group or location['version'] != version
                    or repo_path(repo, path, location['url']) != canonical(repo, group, module, version)):
                raise ValueError('Gradle available-at must name an exact same-module target')
            seen_targets.add(module)
        for entry in variant.get('files', ()):
            file = repo_path(repo, path, entry['url'])
            if file.parent != path.parent or file.stat().st_size != entry['size']:
                raise ValueError('Gradle file size or path mismatch')
            validate_file_name(entry, file, artifact, root_artifact, version)
            if logical_names.setdefault(entry['name'], file.name) != file.name:
                raise ValueError('ambiguous Gradle logical artifact name')
            with file.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != entry['sha256']:
                    raise ValueError('Gradle file checksum mismatch')
            seen_files.add(file.name)
    if seen_targets != set(expected_targets):
        raise ValueError(f'Gradle metadata omits same-module target references: {sorted(set(expected_targets) - seen_targets)}')
    if dependency_group and not found_dependency:
        raise ValueError(f'no published Core edge in {path.name}')
    return seen_files


def verify(repository, manifest, lane, version):
    validate_version(version)
    if not repository.is_dir() or repository.is_symlink() or any(p.is_symlink() for p in repository.rglob('*')):
        raise ValueError('expected a real isolated staging repository without symlinks')
    repo = repository.resolve()
    if manifest['version'] != version:
        raise ValueError('manifest disagrees with the explicit expected version')
    group = manifest['group']
    report = inspect(repo, manifest)
    modules = manifest['production'] + manifest['optInTestOnly'] + [manifest['umbrella']]
    suffixes = ('', '-jvm', '-android') if lane == 'android' else ('', '-jvm')
    paths = {canonical(repo, group, module + suffix, version): (module, suffix)
             for module in modules for suffix in suffixes}
    if set(paths) != set(repo.rglob('*.module')):
        raise ValueError(f'missing or unexpected staged Gradle modules for {lane}')
    expected_poms = {path.with_suffix('.pom').relative_to(repo).as_posix() for path in paths}
    if expected_poms != set(report['pomSha256']):
        raise ValueError(f'missing or unexpected staged POM variants for {lane}')
    if any(path.parent.name == version for path in repo.rglob('maven-metadata.xml')):
        raise ValueError('unexpected version-directory Maven metadata for immutable rehearsal')
    for path, (root_artifact, variant) in sorted(paths.items()):
        artifact = root_artifact + variant
        targets = {root_artifact + suffix for suffix in suffixes if suffix} if not variant else ()
        files = inspect_module(repo, path, group, version, artifact,
                               root_artifact=root_artifact, expected_targets=targets)
        suffix = '.aar' if artifact.endswith('-android') else '.jar'
        if f'{artifact}-{version}{suffix}' not in files:
            raise ValueError(f'Gradle metadata omits the primary artifact: {artifact}')
    return len(paths), report['publicationCount']


def verify_android_uppers(repository, version):
    validate_version(version)
    if not repository.is_dir() or repository.is_symlink() or any(p.is_symlink() for p in repository.rglob('*')):
        raise ValueError('expected the isolated Android upper Maven repository')
    repo = repository.resolve()
    group = 'example.madcore.upper'
    for artifact in ('alpha', 'beta'):
        path = canonical(repo, group, artifact, '0.1.0')
        files = inspect_module(repo, path, group, '0.1.0', artifact,
                               dependency_group='com.mad.core', dependency_version=version)
        if f'{artifact}-0.1.0.aar' not in files:
            raise ValueError('upper Android AAR missing from metadata')
        pom = ET.parse(path.with_suffix('.pom')).getroot()
        ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
        def coordinate(element):
            return tuple(element.findtext(f'm:{key}', namespaces=ns) for key in ('groupId', 'artifactId', 'version'))
        core = [coordinate(dep) for dep in pom.findall('m:dependencies/m:dependency', ns)
                if coordinate(dep)[0] == 'com.mad.core']
        if coordinate(pom) != (group, artifact, '0.1.0') or len(core) != 1 or (
            core[0][1] not in ('madcore', 'madcore-android') or core[0][2] != version
        ):
            raise ValueError(f'wrong published Core POM edge for {artifact}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('prepare', 'verify', 'verify-android-uppers'))
    parser.add_argument('path', type=Path)
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--lane', choices=('jvm', 'android'))
    args = parser.parse_args()
    try:
        if args.mode == 'prepare' and not (args.manifest or args.lane):
            prepare(args.path, args.expected_version)
            print(f'Prepared locked local immutable rehearsal of {REVISION[:8]}; no artifact built')
        elif args.mode == 'verify' and args.manifest and args.lane:
            modules, poms = verify(args.path, json_file(args.manifest), args.lane, args.expected_version)
            print(f'{args.lane}: verified {modules} Gradle metadata files and {poms} staged POMs')
        elif args.mode == 'verify-android-uppers' and not (args.manifest or args.lane):
            verify_android_uppers(args.path, args.expected_version)
            print('Alpha/Beta Maven metadata request only the expected Core coordinate')
        else:
            raise ValueError('invalid mode arguments')
    except (OSError, ValueError, TypeError, KeyError, ET.ParseError) as error:
        sys.exit(f'Immutable Maven rehearsal: {error}')


if __name__ == '__main__':
    main()
