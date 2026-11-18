"""Require native HTTP and TLS rejection execution, never accept skipped/absent cases."""
from pathlib import Path
import xml.etree.ElementTree as ET
required = {'actualLoopbackRequestsAndPolicies', 'untrustedTlsIsRejected'}
seen = set()
for report in Path('core-net/build/test-results/iosSimulatorArm64Test').glob('*.xml'):
    for case in ET.parse(report).iter('testcase'):
        if 'IosUrlSessionTransportTest' not in case.get('classname', ''):
            continue
        name = case.get('name', '').split('[')[0]
        if name in required:
            assert not any(case.find(tag) is not None for tag in ('skipped', 'failure', 'error')), 'Native HTTP test did not pass'
            seen.add(name)
assert seen == required, 'Missing native HTTP/TLS behavior tests: ' + str(required - seen)
print(f'Native iOS HTTP behavior: {len(seen)} required cases passed')
