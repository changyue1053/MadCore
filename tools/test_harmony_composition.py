"""Synthetic archive checks only; does not create actual HAR/HAP binaries."""
import tempfile
from pathlib import Path
from zipfile import ZipFile
from check_harmony_composition import check

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    def write(name, entries):
        path = root / name
        with ZipFile(path, 'w') as archive:
            for entry in entries:
                archive.writestr(entry, b'test')
        return path
    core = write('core.har', ['libs/arm64-v8a/libmadcore.so', 'libs/arm64-v8a/libmadcore_napi.so'])
    alpha = write('alpha.har', ['package/Index.ets'])
    beta = write('beta.har', ['package/Index.d.ets'])
    hap = write('entry.hap', ['libs/arm64-v8a/libmadcore.so', 'libs/arm64-v8a/libmadcore_napi.so'])
    check(core, alpha, beta, hap)
    def rejected():
        try:
            check(core, alpha, beta, hap)
        except ValueError:
            return
        raise AssertionError('Invalid composition accepted')
    write('alpha.har', ['package/Index.ets', 'libs/core.har']); rejected()
    write('alpha.har', ['package/Index.ets', 'libs/libmadcore.so']); rejected()
    write('alpha.har', ['package/Index.ets'])
    write('entry.hap', ['libs/a/libmadcore.so', 'libs/b/libmadcore.so', 'libs/a/libmadcore_napi.so']); rejected()
    write('entry.hap', ['libs/a/libmadcore.so']); rejected()
print('Synthetic Harmony composition archive tests passed; no actual packaging executed')
