"""Fail on missing, extra, empty or incomplete KGP 2.2.21 candidate dump sets.

This is an inventory preflight, not a compiler ABI validator. The Gradle
checkLegacyAbi task remains responsible for comparing declaration contents.
"""
import argparse
import json
from pathlib import Path
import re
import sys

LANES = ('jvm', 'android', 'ios')
IOS_TARGETS = {'iosArm64', 'iosSimulatorArm64'}


def verify(root, lane, kind):
    sdk = json.loads((root / 'SDK-MODULES.json').read_text(encoding='utf-8'))
    modules = [*sdk['production'], sdk['umbrella']]
    if kind == 'reference':
        lane_dir = root / 'api-baseline' / lane
        extras = {p.relative_to(lane_dir).parts[0] for p in lane_dir.rglob('*.api')
                  if p.is_file()} - set(modules)
        if extras:
            raise ValueError(f'Unexpected reference modules in {lane}: {sorted(extras)}')
    for module in modules:
        if kind == 'actual':
            folder = root / module / 'build/api-baseline' / lane
        else:
            folder = root / 'api-baseline' / lane / module
        if lane == 'android':
            names = {f'android/{module}.api', f'jvm/{module}.api'}
        elif lane == 'ios':
            names = {f'{module}.api', f'{module}.klib.api'}
        else:
            names = {f'{module}.api'}
        found = {str(p.relative_to(folder)) for p in folder.rglob('*.api') if p.is_file()}
        if names != found:
            raise ValueError(f'{module}/{lane}/{kind}: missing {sorted(names-found)}, extra {sorted(found-names)}')
        for name in sorted(names):
            data = (folder / name).read_text(encoding='utf-8')
            if not data.strip():
                raise ValueError(f'Empty {lane}/{kind} dump: {module}/{name}')
            if name.endswith('.klib.api'):
                # Only the root header declares the complete target set.
                header = data.splitlines()[:2]
                match = re.fullmatch(r'// Targets: \[([^]]*)\]', header[1]) if len(header) == 2 else None
                actual = [part.strip() for part in match[1].split(',')] if match else []
                if not header or header[0] != '// Klib ABI Dump' \
                        or set(actual) != IOS_TARGETS or len(actual) != len(IOS_TARGETS):
                    raise ValueError(f'Expected both real iOS targets in KLIB dump: {module}/{name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane', choices=LANES)
    parser.add_argument('kind', choices=('actual', 'reference'))
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        verify(args.root, args.lane, args.kind)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'ABI candidate inventory failed: {error}')
    print(f'{args.lane}: complete {args.kind} candidate inventory (signatures not compared)')


if __name__ == '__main__':
    main()
