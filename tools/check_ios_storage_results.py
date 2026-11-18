"""Require the actual native Foundation storage test, not compilation alone."""
from pathlib import Path
import xml.etree.ElementTree as ET
cases = []
for path in Path("core-storage/build/test-results/iosSimulatorArm64Test").rglob("*.xml"):
    for case in ET.parse(path).iter("testcase"):
        if "nativeDefaultsRoundTripAndTypeSafety" in case.get("name", ""):
            cases.append(case)
if not cases or any(any(c.tag in ("failure", "error", "skipped") for c in case) for case in cases):
    raise SystemExit("iOS native storage test absent or unsuccessful")
print(f"Native iOS storage behavior: {len(cases)} passed case(s)")
