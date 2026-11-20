"""Reject native/Core payloads in the two thin upper AAR artifacts."""
import io
from pathlib import Path
import sys
import zipfile

for name in ('alpha-release.aar', 'beta-release.aar'):
    path = Path(sys.argv[1]) / name
    with zipfile.ZipFile(path) as aar:
        if 'classes.jar' not in aar.namelist():
            raise SystemExit('Missing upper SDK bytecode')
        for entry in aar.namelist():
            if entry.endswith('.so'):
                raise SystemExit('Thin upper SDK must not embed native runtimes')
            if entry.endswith('.jar'):
                with zipfile.ZipFile(io.BytesIO(aar.read(entry))) as jar:
                    if any(n.startswith('com/mad/core/') for n in jar.namelist()):
                        raise SystemExit('Upper SDK embeds Core classes')
    print(f'Independent thin AAR checked: {name}')
