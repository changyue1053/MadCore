"""Require all resource-ownership cases in the native Simulator report."""
from pathlib import Path
import xml.etree.ElementTree as ET
required = {
    "lifoDetachAndIdempotentClose",
    "failuresAreIsolatedAndReentrancyCannotReclaimOwnedResources",
    "fatalFailureIsRethrownAfterRemainingCleanup",
    "rejectionDoesNotTakeOwnershipAndDuplicatesAreExplicit",
}
seen = set()
for path in Path("core-lifecycle/build/test-results/iosSimulatorArm64Test").rglob("*.xml"):
    for case in ET.parse(path).iter("testcase"):
        if case.get("classname") == "iosSimulatorArm64Test.com.mad.core.lifecycle.ResourceScopeTest":
            name = case.get("name", "").split("[", 1)[0]
            if name in required:
                if any(c.tag in ("failure", "error", "skipped") for c in case):
                    raise SystemExit("Native lifecycle case unsuccessful")
                seen.add(name)
if seen != required:
    raise SystemExit("Native lifecycle cases absent: " + str(required - seen))
print(f"Native lifecycle ownership: {len(seen)} required cases passed")
