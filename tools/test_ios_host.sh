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
assert plistlib.loads((bundle/'PrivacyInfo.xcprivacy').read_bytes())['NSPrivacyAccessedAPITypes']
PY
xcrun --sdk iphonesimulator swiftc -parse-as-library "$work/App.swift" \
  -target arm64-apple-ios15.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -F "$framework" -framework MadCore -framework Foundation -framework UIKit \
  -Xlinker -ObjC -lc++ -o "$app/MadCoreHost"
# Test-only ad-hoc simulator signature, never a distribution identity.
codesign --force --sign - "$app"
xcrun simctl install "$MADCORE_IOS_SIMULATOR_UDID" "$app"
python3 - "$MADCORE_IOS_SIMULATOR_UDID" <<'PY'
import subprocess,sys
result=subprocess.run(['xcrun','simctl','launch','--console','--terminate-running-process',
                       sys.argv[1],'com.mad.consumer.smoke'],
                      stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
print(result.stdout)
assert result.returncode == 0, 'Independent host process failed'
assert result.stdout.splitlines().count('MADCORE_EXTERNAL_IOS_HOST_PASS') == 1, 'Missing or duplicate success marker'
assert 'MADCORE_EXTERNAL_IOS_HOST_FAIL' not in result.stdout, 'Independent host reported failure'
print('Independent artifact-only iOS host executed successfully')
PY
