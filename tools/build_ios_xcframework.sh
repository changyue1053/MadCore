#!/usr/bin/env bash
# Unsigned development artifact packaging, not an App Store compliance certification.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
./gradlew --no-daemon -Pmadcore.target=ios :madcore:assembleMadCoreReleaseXCFramework
python3 - <<'PY'
from pathlib import Path
import plistlib
import shutil
root = Path("madcore/build/XCFrameworks/release/MadCore.xcframework")
source = Path("madcore/apple/PrivacyInfo.xcprivacy")
expected = plistlib.loads(source.read_bytes())
assert expected["NSPrivacyAccessedAPITypes"], "Empty required-reason declaration"
info = plistlib.loads((root / "Info.plist").read_bytes())
slices = info["AvailableLibraries"]
assert len(slices) == 2, "Unexpected XCFramework slice count"
for item in slices:
    framework = root / item["LibraryIdentifier"] / item["LibraryPath"]
    assert framework.is_dir() and (framework / "MadCore").is_file()
    destination = framework / "PrivacyInfo.xcprivacy"
    shutil.copyfile(source, destination)
    assert plistlib.loads(destination.read_bytes()) == expected
    print("Verified required-reason manifest:", item["LibraryIdentifier"])
PY
