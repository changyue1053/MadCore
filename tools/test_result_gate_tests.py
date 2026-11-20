"""Negative evidence tests, also run with Python optimization enabled."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from test_result_gate import require_cases


class ResultGateTest(unittest.TestCase):
    def check(self, xml, passes=False, target=None):
        with TemporaryDirectory() as tmp:
            if xml is not None:
                (Path(tmp) / 'result.xml').write_text(xml)
            if passes:
                require_cases(tmp, {('app.Test', 'behavior')}, 'fixture', target)
            else:
                with self.assertRaises(SystemExit):
                    require_cases(tmp, {('app.Test', 'behavior')}, 'fixture', target)

    def test_pass_and_native_decoration(self):
        self.check('<testsuite><testcase classname="app.Test" name="behavior"/></testsuite>', True)
        self.check('<testsuite><testcase classname="iosSimulatorArm64Test.app.Test" name="behavior[iosSimulatorArm64]"/></testsuite>', True, 'iosSimulatorArm64')

    def test_absent_empty_malformed_and_wrong_identity(self):
        for xml in (None, '<testsuite/>', '<broken',
                    '<testsuite><testcase classname="other.app.Test" name="behavior"/></testsuite>',
                    '<testsuite><testcase classname="app.Test" name="behaviorExtra"/></testsuite>',
                    '<testsuite><testcase classname="app.Test" name="behavior[anotherTarget]"/></testsuite>'):
            self.check(xml, target='iosSimulatorArm64')

    def test_failed_skipped_and_duplicate_cannot_mask_failure(self):
        for tag in ('failure', 'error', 'skipped'):
            bad = f'<testcase classname="app.Test" name="behavior"><{tag}/></testcase>'
            self.check('<testsuite>' + bad + '</testsuite>')
            self.check('<testsuite><testcase classname="app.Test" name="behavior"/>' + bad + '</testsuite>')

    def test_suite_failures_and_invalid_counts(self):
        for attr in ('failures="1"', 'errors="1"', 'failures="-1"', 'errors="invalid"'):
            self.check(f'<testsuite {attr}><testcase classname="app.Test" name="behavior"/></testsuite>')


if __name__ == '__main__':
    unittest.main()
