"""Require exact native Simulator behavior results, rejecting skipped/absent cases."""
from test_result_gate import require_cases

required = {
    ('com.mad.core.net.IosUrlSessionTransportTest', 'actualLoopbackRequestsAndPolicies'),
    ('com.mad.core.net.IosUrlSessionTransportTest', 'untrustedTlsIsRejected'),
}
require_cases("core-net/build/test-results/iosSimulatorArm64Test", required,
              "Native iOS http behavior", kotlin_target="iosSimulatorArm64Test")
