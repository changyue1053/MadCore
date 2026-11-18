"""Exercise launch failure evidence without pretending to run UIKit."""
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from run_ios_host import launch, PASS, FAIL


class HostRunnerTest(unittest.TestCase):
    def run_case(self, code, expected, passes=False, timeout=5):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / 'host.log'
            if passes:
                launch([sys.executable, '-u', '-c', code], path, timeout)
            else:
                with self.assertRaises(SystemExit):
                    launch([sys.executable, '-u', '-c', code], path, timeout)
            self.assertEqual(path.read_text(), expected)

    def test_success(self):
        self.run_case(f'print({PASS!r})', PASS+'\n', True)

    def test_reject_missing_duplicate_failure_and_nonzero(self):
        for text, exit_code in [('', 0), (PASS+'\n'+PASS, 0), (PASS+'\n'+FAIL, 0), (PASS, 1)]:
            self.run_case(f'print({text!r}); raise SystemExit({exit_code})', text+'\n')

    def test_timeout_retains_output_even_with_pass_marker(self):
        self.run_case(f'import time; print({PASS!r}); time.sleep(30)', PASS+'\n', timeout=0.3)


if __name__ == '__main__':
    unittest.main()
