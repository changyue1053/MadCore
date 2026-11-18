"""Archive-only thin-HAR composition audit. Not device execution or license clearance."""
import sys
import tarfile
import zipfile
from pathlib import PurePosixPath


def names(path):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            return [n for n in archive.namelist() if not n.endswith('/')]
    with tarfile.open(path) as archive:
        return [item.name for item in archive.getmembers() if item.isfile()]


def check(core, alpha, beta, hap):
    expected = {'libmadcore.so', 'libmadcore_napi.so'}
    for upper in (alpha, beta):
        files = names(upper)
        if any(n.endswith(('.so', '.har', '.hap')) for n in files):
            raise ValueError('Upper SDK embeds native or nested artifact payload')
        if not any(n.endswith(('Index.ets', 'Index.d.ets', 'Index.d.ts')) for n in files):
            raise ValueError('Upper SDK entry absent')
    for archive in (core, hap):
        files = names(archive)
        for library in expected:
            if sum(PurePosixPath(n).name == library for n in files) != 1:
                raise ValueError('Expected exactly one packaged copy of ' + library)
    print('Two thin upper HARs and one Core native library pair in unsigned HAP; runtime NOT tested')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        raise SystemExit('Expected core HAR, alpha HAR, beta HAR, unsigned HAP')
    check(*sys.argv[1:])
