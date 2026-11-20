"""Local evidence only, for an existing stable MadCore release XCFramework.

Supply the actual artifact and its build revision; the revision is caller
metadata, not inferred from the binary. Save stdout privately. This does not
build, sign or execute anything, nor determine third-party attribution or rights.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tarfile


SLICES = {'ios-arm64': None, 'ios-arm64-simulator': 'simulator'}


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def identify(path):
    return {'name': path.name, 'size': path.stat().st_size, 'sha256': sha256(path)}


def package(root):
    library = root / 'Info.plist'
    slices = plistlib.loads(library.read_bytes())['AvailableLibraries']
    if len(slices) != len(SLICES) or {item['LibraryIdentifier'] for item in slices} != SLICES.keys():
        raise ValueError('expected exactly the actual MadCore device and simulator slices')
    result = {}
    for item in slices:
        name = item['LibraryIdentifier']
        if (item['SupportedPlatform'] != 'ios' or item.get('SupportedPlatformVariant') != SLICES[name]
                or item['SupportedArchitectures'] != ['arm64'] or item['LibraryPath'] != 'MadCore.framework'):
            raise ValueError(f'unexpected slice metadata: {name}')
        directory = root / name
        framework = directory / item['LibraryPath']
        archive = framework / 'MadCore'
        for path in (directory, framework, archive, framework / 'Headers' / 'MadCore.h',
                     framework / 'PrivacyInfo.xcprivacy'):
            if path.is_symlink() or not path.exists():
                raise ValueError(f'expected a real packaged path: {path}')
        with archive.open('rb') as stream:
            if stream.read(8) != b'!<arch>\n':
                raise ValueError(f'not a regular static archive: {name}')
        members = subprocess.run(['ar', '-t', str(archive)], check=True, text=True,
                                 capture_output=True).stdout.splitlines()
        if not members:
            raise ValueError(f'empty static archive: {name}')
        result[name] = {'static_archive_members': members}
    # Preserve link entries as links; do not follow them into the filesystem.
    files = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            files[relative] = {'symlink': str(path.readlink())}
        elif path.is_file():
            files[relative] = identify(path)
        elif not path.is_dir():
            raise ValueError(f'unsupported packaged entry: {relative}')
    return {'slices': result, 'packaged_files': files}


def host(executable, map_path, slice_name):
    text = map_path.read_text(encoding='utf-8')
    before, _, after = text.partition('# Object files:\n')
    objects, _, sections = after.partition('# Sections:\n')
    path = next((line.removeprefix('# Path: ') for line in before.splitlines()
                 if line.startswith('# Path: ')), '')
    if (Path(path).name != executable.name or '# Arch: arm64' not in before.splitlines()
            or not objects.strip() or '# Symbols:\n' not in sections):
        raise ValueError('expected an arm64 Apple linker map for the named host executable')
    if not any(re.search(r'MadCore\.framework/MadCore\(', line) for line in objects.splitlines()):
        raise ValueError('linker map does not identify any MadCore archive members')
    return {'slice_as_supplied': slice_name, 'executable': identify(executable),
            'link_map': identify(map_path), 'link_map_loaded_objects': objects.splitlines()}


def supplier(archive, kotlin_version):
    # Stock official Maven arm64 host artifact, not a similarly named CDN package.
    if archive.name != f'kotlin-native-prebuilt-{kotlin_version}-macos-aarch64.tar.gz':
        raise ValueError('supply the exact cached KGP Maven Kotlin/Native prebuilt archive')
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        evidence = []
        for member in members:
            name = Path(member.name).name.lower()
            if name.startswith(('license', 'notice', 'third-party', 'third_party', 'copyright')) or (
                name == "manifest" and "klib" in Path(member.name).parts
            ):
                digest = None
                if member.isfile():
                    with tar.extractfile(member) as stream:
                        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
                evidence.append({'name': member.name, 'size': member.size, 'sha256': digest})
    if not members:
        raise ValueError('empty supplier archive')
    return {'archive': identify(archive), 'archive_member_count': len(members),
            'notice_and_klib_manifest_candidates': evidence}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--xcframework', required=True, type=Path)
    parser.add_argument('--source-revision', required=True, help='exact 40-character stable producer commit')
    parser.add_argument('--kotlin-version', required=True, help='actual stable producer Kotlin version')
    parser.add_argument('--host-executable', type=Path)
    parser.add_argument('--host-link-map', type=Path)
    parser.add_argument('--host-slice', choices=SLICES)
    parser.add_argument('--supplier-archive', type=Path)
    args = parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}', args.source_revision) or not re.fullmatch(r'\d+\.\d+\.\d+', args.kotlin_version):
        parser.error('supply exact stable source SHA and numeric Kotlin release version')
    if any([args.host_executable, args.host_link_map, args.host_slice]) != all(
        [args.host_executable, args.host_link_map, args.host_slice]
    ):
        parser.error('supply host executable, map and slice together')
    try:
        evidence = {'source_revision_as_supplied': args.source_revision, 'kotlin_version_as_supplied': args.kotlin_version,
                    'xcframework': package(args.xcframework.resolve())}
        if args.host_executable:
            evidence['host'] = host(args.host_executable, args.host_link_map, args.host_slice)
        if args.supplier_archive:
            evidence['supplier'] = supplier(args.supplier_archive, args.kotlin_version)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, tarfile.TarError) as error:
        parser.exit(1, f'iOS evidence capture failed: {error}\n')
    print(json.dumps(evidence, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
