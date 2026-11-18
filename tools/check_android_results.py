"""Fail closed if the actual independent emulator test was skipped or absent."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
cases = []
for path in Path(sys.argv[1]).rglob("*.xml"):
    for case in ET.parse(path).iter("testcase"):
        if case.get("classname") == "com.mad.consumer.CoreIntegrationTest" and case.get("name") == "publishedCoreAndRealHttp":
            cases.append(case)
if not cases or any(any(c.tag in ("failure", "error", "skipped") for c in case) for case in cases):
    raise SystemExit("Android independent HTTP behavior test absent or unsuccessful")
print(f"Independent Android emulator HTTP behavior: {len(cases)} passed case(s)")
