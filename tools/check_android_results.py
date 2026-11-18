"""Require every independent emulator behavior case, rejecting skipped/absent results."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
required = {
    ("com.mad.consumer.CoreIntegrationTest", "publishedCoreAndRealHttp"),
    ("com.mad.consumer.StorageIntegrationTest", "publishedStorageAndPlatformPersistence"),
    ("com.mad.consumer.StorageIntegrationTest", "failedCommitsAndPlatformErrorsAreRedacted"),
}
seen = set()
for path in Path(sys.argv[1]).rglob("*.xml"):
    for case in ET.parse(path).iter("testcase"):
        key = (case.get("classname"), case.get("name"))
        if key in required:
            if any(c.tag in ("failure", "error", "skipped") for c in case):
                raise SystemExit("Android independent behavior case unsuccessful")
            seen.add(key)
if seen != required:
    raise SystemExit("Android independent behavior cases absent: " + str(required - seen))
print(f"Independent Android emulator behavior: {len(seen)} required cases passed")
