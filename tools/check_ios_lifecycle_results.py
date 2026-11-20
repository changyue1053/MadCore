"""Require exact native Simulator behavior results, rejecting skipped/absent cases."""
from test_result_gate import require_cases

required = {
    ('com.mad.core.lifecycle.ResourceScopeTest', 'lifoDetachAndIdempotentClose'),
    ('com.mad.core.lifecycle.ResourceScopeTest', 'failuresAreIsolatedAndReentrancyCannotReclaimOwnedResources'),
    ('com.mad.core.lifecycle.ResourceScopeTest', 'fatalFailureIsRethrownAfterRemainingCleanup'),
    ('com.mad.core.lifecycle.ResourceScopeTest', 'rejectionDoesNotTakeOwnershipAndDuplicatesAreExplicit'),
}
require_cases("core-lifecycle/build/test-results/iosSimulatorArm64Test", required,
              "Native iOS lifecycle behavior", kotlin_target="iosSimulatorArm64")
