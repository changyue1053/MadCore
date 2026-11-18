"""Fail closed unless the native HTTP behavior test actually executed successfully."""
from pathlib import Path
import xml.etree.ElementTree as ET

reports = list(Path('core-net/build/test-results/iosSimulatorArm64Test').glob('*.xml'))
assert reports, 'Missing iOS Simulator JUnit reports'
matched = []
for report in reports:
    root = ET.parse(report).getroot()
    for case in root.iter('testcase'):
        if 'IosUrlSessionTransportTest' in case.get('classname', '') and 'actualLoopbackRequestsAndPolicies' in case.get('name', ''):
            assert not any(case.find(tag) is not None for tag in ('skipped', 'failure', 'error')), 'Native HTTP test did not pass'
            matched.append(case)
assert matched, 'Native HTTP behavior test was not executed'
print(f'Native iOS HTTP behavior test: {len(matched)} passed case(s)')
