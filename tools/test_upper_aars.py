import io
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
import zipfile


class UpperAarTest(unittest.TestCase):
    def test_clean_and_embedded_core_rejected(self):
        for embedded in (False, True):
            with TemporaryDirectory() as tmp:
                root = Path(tmp)
                for name in ('alpha', 'beta'):
                    content = io.BytesIO()
                    with zipfile.ZipFile(content, 'w') as jar:
                        jar.writestr('example/Upper.class', b'fake-test')
                        if embedded:
                            jar.writestr('com/mad/core/storage/StringStore.class', b'fake-test')
                    with zipfile.ZipFile(root / f'{name}-release.aar', 'w') as aar:
                        aar.writestr('classes.jar', content.getvalue())
                result = subprocess.run([sys.executable, str(Path(__file__).with_name('check_upper_aars.py')), str(root)], capture_output=True)
                self.assertEqual(result.returncode == 0, not embedded)


if __name__ == '__main__':
    unittest.main()
