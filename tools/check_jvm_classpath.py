"""Reject duplicate MadCore classes; this is not an API compatibility validator."""
import json
from pathlib import Path
import sys
import zipfile

def check(paths):
    owners = {}
    for raw in paths:
        path = Path(raw)
        if path.is_dir():
            names = [str(p.relative_to(path)).replace('\\', '/') for p in path.rglob('*.class')]
        elif zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
        else:
            raise ValueError('Classpath entry is not a class directory or archive')
        for name in names:
            if name.startswith('com/mad/core/') and name.endswith('.class'):
                if name in owners:
                    raise ValueError('Duplicate MadCore class: ' + name)
                owners[name] = path
    if not owners:
        raise ValueError('No MadCore classes found; empty validation is not a pass')
    return len(owners)

if __name__ == '__main__':
    print(f'Unique MadCore JVM classes: {check(json.loads(Path(sys.argv[1]).read_text()))}; not binary compatibility proof')
