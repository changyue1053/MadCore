import hashlib
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest
from inventory_harmony_binary import inspect, main


class InventoryTest(unittest.TestCase):
    def test_real_host_elf_and_invalid_input(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'test.c'
            source.write_text('#include <stdio.h>\nvoid probe(void) { puts("probe"); }\n')
            artifact = root / 'libprobe.so'
            subprocess.run(['cc', '-shared', '-fPIC', str(source), '-Wl,-soname,libprobe.so', '-o', str(artifact)], check=True)
            data = inspect(artifact)
            self.assertEqual(data['sha256'], hashlib.sha256(artifact.read_bytes()).hexdigest())
            self.assertEqual(data['soname'], ['libprobe.so'])
            self.assertIn('libc.so.6', data['needed'])
            with self.assertRaises(ValueError):
                inspect(source)
            with self.assertRaises(FileNotFoundError):
                main(root, root / 'out.json')


if __name__ == '__main__':
    unittest.main()
