"""Compare actual KGP 2.2.21 and 2.3.21 dumps; do not create references."""
import argparse
from difflib import unified_diff
import json
from pathlib import Path
import re
import sys

from check_abi_candidate_inventory import LANES, verify


def rendering_settings(data):
    """Fail closed if a KLIB renderer's signature version/options are unknown."""
    lines = data.splitlines()
    try:
        begin = lines.index('// Rendering settings:') + 1
    except ValueError:
        return None
    options = []
    for line in lines[begin:]:
        if not line.startswith('// - '):
            break
        options.append(line)
    signatures = [line for line in options if re.fullmatch(r'// - Signature version: \d+', line)]
    return tuple(options) if len(signatures) == 1 else None


def compare(lane, current, proposed, out, counts):
    """Emit raw differences to out; count mutually exclusive status rows."""
    roots = {'2.2.21': current.resolve(), '2.3.21': proposed.resolve()}
    if roots['2.2.21'] == roots['2.3.21']:
        print('INCOMPLETE: supply two independent actual dump trees', file=out)
        counts["incomplete"] += 1
        return
    manifests = {}
    for version, root in roots.items():
        try:
            verify(root, lane, 'actual')
            if (root / 'core-testkit' / 'build/api-baseline' / lane).exists():
                raise ValueError('unexpected opt-in testkit output')
            manifests[version] = json.loads((root / 'SDK-MODULES.json').read_text(encoding='utf-8'))
        except (OSError, KeyError, ValueError) as error:
            print(f'INCOMPLETE OR FORMAT MISMATCH {version}/{lane}: {error}', file=out)
            counts["incomplete"] += 1
    if counts["incomplete"]:
        return
    if manifests['2.2.21'] != manifests['2.3.21']:
        print('INCOMPLETE: module manifests differ; compare the same source revision', file=out)
        counts["incomplete"] += 1
        return

    sdk = manifests['2.2.21']
    for module in [*sdk['production'], sdk['umbrella']]:
        directory = Path(module) / 'build/api-baseline' / lane
        for file in sorted((roots['2.2.21'] / directory).rglob('*.api')):
            relative = file.relative_to(roots['2.2.21'])
            baseline = file.read_bytes().decode('utf-8')
            candidate = (roots['2.3.21'] / relative).read_bytes().decode('utf-8')
            concern = None
            if lane == 'android' and file.parent.name == 'android':
                concern = 'Android input scope differs: non-test class dirs versus release only'
            elif file.name.endswith('.klib.api'):
                settings = rendering_settings(baseline)
                if settings is None or settings != rendering_settings(candidate):
                    concern = 'KLIB rendering/signature settings mismatch or unrecognized header'
            label = '/'.join([module, file.relative_to(roots['2.2.21'] / directory).as_posix()])
            if concern:
                print(f'NOT COMPARABLE {lane}/{label}: {concern}', file=out)
                counts["noncomparable"] += 1
            elif baseline == candidate:
                counts["identical"] += 1
            else:
                counts["changed"] += 1
            if baseline == candidate:
                print(f'IDENTICAL DUMP TEXT {lane}/{label}', file=out)
                continue
            print(f'CHANGED DUMP TEXT {lane}/{label}' + (' (diagnostic only)' if concern else ''), file=out)
            for line in unified_diff(baseline.splitlines(keepends=True), candidate.splitlines(keepends=True),
                                     fromfile=f'2.2.21/{label}', tofile=f'2.3.21/{label}'):
                out.write(line if line.endswith('\n') else line + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lane', choices=LANES)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('overlay', type=Path)
    parser.add_argument('--private-report', required=True, type=Path)
    args = parser.parse_args()
    counts = dict(identical=0, changed=0, noncomparable=0, incomplete=0)
    with args.private_report.open('x', encoding='utf-8') as report:
        compare(args.lane, args.baseline, args.overlay, report, counts)
    print(f"ABI {args.lane}: " + ", ".join(f"{key}={count}" for key, count in counts.items()))
    sys.exit(1 if counts['incomplete'] else 0)


if __name__ == '__main__':
    main()
