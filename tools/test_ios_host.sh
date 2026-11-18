#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
: "${MADCORE_IOS_SIMULATOR_UDID:?Boot a simulator and set its UDID}"
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/madcore-ios-host.XXXXXXXX")
cleanup() {
  python3 - "$MADCORE_IOS_SIMULATOR_UDID" <<'CLEANUP' || true
import subprocess,sys
for action in ('terminate', 'uninstall'):
    try:
        subprocess.run(['xcrun','simctl',action,sys.argv[1],'com.mad.consumer.smoke'],
                       stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
    except subprocess.TimeoutExpired:
        pass
CLEANUP
  rm -rf -- "$work"
}
trap cleanup EXIT
cp -R "$root/madcore/build/XCFrameworks/release/MadCore.xcframework" "$work/"
cp "$root/examples/ios-host/App.swift" "$work/App.swift"
app="$work/MadCoreHost.app"
mkdir -p "$app/MadCorePrivacy.bundle"
cp "$root/examples/ios-host/Info.plist" "$app/Info.plist"
framework="$work/MadCore.xcframework/ios-arm64-simulator"
cp "$framework/MadCore.framework/PrivacyInfo.xcprivacy" "$app/MadCorePrivacy.bundle/PrivacyInfo.xcprivacy"
python3 - "$app/MadCorePrivacy.bundle" <<'PY'
import plistlib,sys,pathlib
bundle=pathlib.Path(sys.argv[1])
(bundle/'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'com.mad.core.privacy',
    'CFBundleName':'MadCorePrivacy',
    'CFBundlePackageType':'BNDL',
    'CFBundleVersion':'1'
}))
if not plistlib.loads((bundle/'PrivacyInfo.xcprivacy').read_bytes()).get('NSPrivacyAccessedAPITypes'):
    raise SystemExit('Missing privacy declarations')
PY
echo "Independent host compilation $(date -u +%FT%TZ)"
xcrun --sdk iphonesimulator swiftc -parse-as-library "$work/App.swift" \
  -target arm64-apple-ios15.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -F "$framework" -framework MadCore -framework Foundation -framework UIKit \
  -Xlinker -ObjC -lc++ -o "$app/MadCoreHost"
# Test-only ad-hoc simulator signature, never a distribution identity.
codesign --force --sign - "$app"
echo "Independent host installation $(date -u +%FT%TZ)"
xcrun simctl install "$MADCORE_IOS_SIMULATOR_UDID" "$app"
echo "Independent host launch $(date -u +%FT%TZ)"
python3 "$root/tools/run_ios_host.py" "$MADCORE_IOS_SIMULATOR_UDID" "${RUNNER_TEMP:-/tmp}/madcore-ios-host.log"
