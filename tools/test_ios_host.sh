#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
: "${MADCORE_IOS_SIMULATOR_UDID:?Boot a simulator and set its UDID}"
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/madcore-ios-host.XXXXXXXX")
cleanup() {
  python3 - "$MADCORE_IOS_SIMULATOR_UDID" "$work/simulator-install-attempted" <<'CLEANUP' || true
import pathlib,subprocess,sys
# A rejected expectation or failed compile cannot act on the simulator.
if not pathlib.Path(sys.argv[2]).is_file():
    sys.exit(0)
for action, bundle in [(a, b) for b in ('com.mad.consumer.smoke', 'com.mad.consumer.control') for a in ('terminate', 'uninstall')]:
    try:
        subprocess.run(['xcrun','simctl',action,sys.argv[1],bundle],
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
# Keep this expectation outside the SDK binary and out of its packaged metadata.
python3 -B "$root/tools/configure_ios_host_version.py" "$root/SDK-MODULES.json" "$app/Info.plist" "$@"
# Compile two separate upper-SDK static archives, then consume only their
# archives/module interfaces and one shared MadCore framework in the host.
upper="$work/upper-artifacts"
mkdir -p "$upper"
for module in FeatureAlpha FeatureBeta; do
  cp "$root/examples/ios-upper-sdks/$module.swift" "$work/$module.swift"
  xcrun --sdk iphonesimulator swiftc -parse-as-library -emit-library -static -emit-module \
    -module-name "$module" "$work/$module.swift" \
    -emit-module-path "$upper/$module.swiftmodule" \
    -target arm64-apple-ios15.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -F "$framework" -o "$upper/lib$module.a"
  test -s "$upper/lib$module.a"
  rm "$work/$module.swift"
done
echo "Independent host compilation $(date -u +%FT%TZ)"
xcrun --sdk iphonesimulator swiftc -parse-as-library "$work/App.swift" \
  -target arm64-apple-ios15.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -I "$upper" -L "$upper" -lFeatureAlpha -lFeatureBeta \
  -F "$framework" -framework MadCore -framework Foundation -framework UIKit \
  -Xlinker -ObjC -lc++ -o "$app/MadCoreHost"
# Test-only ad-hoc simulator signature, never a distribution identity.
codesign --force --sign - "$app"
echo "Independent host installation $(date -u +%FT%TZ)"
: > "$work/simulator-install-attempted"
xcrun simctl install "$MADCORE_IOS_SIMULATOR_UDID" "$app"
# Same UIKit launch/console route with no SDK, for diagnosis, not a replacement test.
control="$work/MadCoreControl.app"
mkdir -p "$control"
python3 - "$root/examples/ios-host/Info.plist" "$control/Info.plist" <<'CONTROL'
import plistlib,sys
with open(sys.argv[1], 'rb') as f:
    info=plistlib.load(f)
info.update(CFBundleIdentifier='com.mad.consumer.control', CFBundleExecutable='MadCoreControl', CFBundleName='MadCoreControl')
info.pop('NSAppTransportSecurity', None)
with open(sys.argv[2], 'wb') as f:
    plistlib.dump(info, f)
CONTROL
xcrun --sdk iphonesimulator swiftc -parse-as-library "$root/examples/ios-control/App.swift" \
  -target arm64-apple-ios15.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -framework Foundation -framework UIKit -o "$control/MadCoreControl"
codesign --force --sign - "$control"
xcrun simctl install "$MADCORE_IOS_SIMULATOR_UDID" "$control"
control_status=0
python3 "$root/tools/run_ios_host.py" "$MADCORE_IOS_SIMULATOR_UDID" "${RUNNER_TEMP:-/tmp}/madcore-ios-control.log" \
  com.mad.consumer.control MADCORE_CONTROL_PASS || control_status=$?
echo "Independent host launch $(date -u +%FT%TZ)"
host_status=0
host_log="${RUNNER_TEMP:-/tmp}/madcore-ios-host.log"
python3 "$root/tools/run_ios_host.py" "$MADCORE_IOS_SIMULATOR_UDID" "$host_log" || host_status=$?
if [ "$host_status" -eq 0 ]; then
  if [ "$(grep -Fxc 'MADCORE_HOST_VERSION_MATCH' "$host_log" || true)" != 1 ] ||
      grep -Fxq 'MADCORE_HOST_VERSION_MISMATCH' "$host_log"; then
    echo 'Independent host version marker was missing, duplicated or contradictory'
    host_status=1
  fi
fi
if [ "$control_status" -ne 0 ] || [ "$host_status" -ne 0 ]; then
  python3 "$root/tools/ios_launch_diagnostics.py" "$MADCORE_IOS_SIMULATOR_UDID" || true
  echo "Control status=$control_status; SDK host status=$host_status (both required)"
  exit 1
fi
