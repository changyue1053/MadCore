"""Fail-closed JUnit evidence checks. A build or an empty report is not execution."""
from pathlib import Path
import xml.etree.ElementTree as ET


def require_cases(directory, required, label, kotlin_target=None):
    """Require exact class/method pairs; normalize only Kotlin's target decoration.

    Reject any reported failure/error/skip for required cases, including duplicate
    attempts. Suite-level failures also fail, even if individual cases look green.
    Report freshness is the caller's responsibility (CI uses clean checkouts).
    """
    seen = set()
    reports = sorted(Path(directory).rglob("*.xml"))
    for path in reports:
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, OSError) as error:
            raise SystemExit(f"{label}: unreadable test report") from error
        for suite in root.iter():
            if suite.tag not in ("testsuite", "testsuites"):
                continue
            for attribute in ("failures", "errors"):
                try:
                    value = int(suite.get(attribute, "0"))
                except ValueError as error:
                    raise SystemExit(f"{label}: invalid suite result count") from error
                if value != 0:
                    raise SystemExit(f"{label}: suite reports {attribute}")
        for case in root.iter("testcase"):
            classname, name = case.get("classname", ""), case.get("name", "")
            if kotlin_target:
                prefix, suffix = kotlin_target + ".", "[" + kotlin_target + "]"
                if classname.startswith(prefix):
                    classname = classname[len(prefix):]
                if name.endswith(suffix):
                    name = name[:-len(suffix)]
            key = (classname, name)
            if key not in required:
                continue
            if any(child.tag in ("failure", "error", "skipped") for child in case):
                raise SystemExit(f"{label}: required case unsuccessful")
            seen.add(key)
    if seen != required:
        raise SystemExit(f"{label}: required cases absent: {sorted(required - seen)}")
    print(f"{label}: {len(seen)} required cases passed")
