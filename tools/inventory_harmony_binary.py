"""Build-evidence inventory only, not a static-link SBOM or license clearance."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


def inspect(path):
    path = Path(path)
    data = path.read_bytes()
    if not data.startswith(b'\x7fELF'):
        raise ValueError('Expected ELF artifact')
    header = subprocess.run(['readelf', '-h', str(path)], check=True, text=True,
                            capture_output=True, timeout=15).stdout
    dynamic = subprocess.run(['readelf', '-d', str(path)], check=True, text=True,
                             capture_output=True, timeout=15).stdout
    machine = re.search(r'^\s*Machine:\s*(.+)$', header, re.M)
    if not machine:
        raise ValueError('Missing ELF machine')
    return {'name': path.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'machine': machine.group(1).strip(),
            'needed': sorted(re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', dynamic)),
            'soname': re.findall(r'\(SONAME\).*?\[([^\]]+)\]', dynamic)}


def main(directory, destination):
    items = [inspect(Path(directory) / name) for name in ('libmadcore.so', 'libmadcore_napi.so')]
    if any(item['machine'] != 'AArch64' for item in items):
        raise SystemExit('Harmony package expected AArch64 artifacts')
    report = {'schema': 1, 'scope': 'two generated HAR native libraries before packaging',
              'limitations': ['DT_NEEDED is not a static runtime inventory',
                              'No component license or redistribution inference',
                              'No loadability or device execution proof'], 'artifacts': items}
    path = Path(destination)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main(*sys.argv[1:])
