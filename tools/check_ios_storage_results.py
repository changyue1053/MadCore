"""Require exact native Simulator behavior results, rejecting skipped/absent cases."""
from test_result_gate import require_cases

required = {
    ('com.mad.core.storage.UserDefaultsStringStoreTest', 'nativeDefaultsRoundTripAndTypeSafety'),
}
require_cases("core-storage/build/test-results/iosSimulatorArm64Test", required,
              "Native iOS storage behavior", kotlin_target="iosSimulatorArm64Test")
