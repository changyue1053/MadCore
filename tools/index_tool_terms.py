"""Index names/hashes of license-like files in the already-authorized CLI.
Does not accept terms, copy license contents, or establish permissions/completeness.
"""
import hashlib
import json
from pathlib import Path
import sys

root, output = map(Path, sys.argv[1:])
entries = []
for path in sorted(root.rglob('*')):
    if path.is_symlink() or not path.is_file():
        continue
    name = path.name.lower()
    if not any(word in name for word in ('license', 'licence', 'notice', 'copyright', 'agreement')):
        continue
    size = path.stat().st_size
    if size > 4 * 1024 * 1024:
        entries.append({'path': str(path.relative_to(root)), 'bytes': size, 'hashSkipped': 'size limit'})
        continue
    entries.append({'path': str(path.relative_to(root)), 'bytes': size,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
report = {'schema': 1, 'tool': 'Huawei CLI 5.1.0.840', 'selection': 'filename keyword heuristic, not exhaustive',
          'permissionConclusion': 'none', 'files': entries}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({"tool": report["tool"], "totalFiles": len(entries), "selection": report["selection"],
                  "permissionConclusion": "none", "first100Files": entries[:100]}, indent=2))
