#!/usr/bin/env bash
# Two published upper KLIBs, one application-specific umbrella, one independent Swift host.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:?Usage: build CORE_MAVEN_REPOSITORY OUTPUT_DIR | run OUTPUT_DIR}
bundle=com.mad.consumer.kotlincomposition
if [[ "$mode" == build ]]; then
  repository=${2:?Staged Core Maven repository required}
  output=${3:?Output directory required}
  test -d "$repository"
  repository=$(cd "$repository" && pwd)
  mkdir -p "$output"
  output=$(cd "$output" && pwd)
  # Invalidate stale output before attempting a new build.
  rm -rf -- "$output/CompositionHost.app"
  work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/madcore-kotlin-composition.XXXXXXXX")
  trap 'rm -rf -- "$work"' EXIT
  cp -R "$root/examples/ios-kotlin-composition/producers" "$work/producers"
  cp -R "$root/examples/ios-kotlin-composition/umbrella" "$work/umbrella"
  mkdir -p "$work/upper-repository"
  "$root/gradlew" --no-daemon -p "$work/producers" \
    -PmadcoreRepository="$repository" -PupperRepository="$work/upper-repository" \
    :upper-alpha:publishAllPublicationsToProbeRepository :upper-beta:publishAllPublicationsToProbeRepository
  # Producer source no longer available when the umbrella resolves published KLIBs.
  rm -rf -- "$work/producers"
  "$root/gradlew" --no-daemon -p "$work/umbrella" \
    -PmadcoreRepository="$repository" -PupperRepository="$work/upper-repository" \
    linkReleaseFrameworkIosSimulatorArm64
  mkdir -p "$work/host-artifacts"
  cp -R "$work/umbrella/build/bin/iosSimulatorArm64/releaseFramework/AppComposition.framework" "$work/host-artifacts/"
  rm -rf -- "$work/umbrella" "$work/upper-repository"
  app="$work/CompositionHost.app"
  mkdir -p "$app"
  cp "$root/examples/ios-kotlin-composition/host/Info.plist" "$app/Info.plist"
  cp "$root/examples/ios-kotlin-composition/host/App.swift" "$work/App.swift"
  xcrun --sdk iphonesimulator swiftc -parse-as-library "$work/App.swift" \
    -target arm64-apple-ios15.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -F "$work/host-artifacts" -framework AppComposition -framework Foundation -framework UIKit \
    -Xlinker -ObjC -lc++ -o "$app/CompositionHost"
  codesign --force --sign - "$app"
  cp -R "$app" "$output/CompositionHost.app"
  echo 'Two published KLIBs linked into one app-specific framework; Swift host built, NOT executed'
elif [[ "$mode" == run ]]; then
  output=${2:?Output directory required}
  : "${MADCORE_IOS_SIMULATOR_UDID:?Boot simulator and supply UDID}"
  test -s "$output/CompositionHost.app/CompositionHost"
  cleanup() {
    python3 - "$MADCORE_IOS_SIMULATOR_UDID" "$bundle" <<'CLEANUP'
import subprocess,sys
for action in ('terminate','uninstall'):
    try:
        subprocess.run(['xcrun','simctl',action,sys.argv[1],sys.argv[2]], stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
    except subprocess.TimeoutExpired:
        pass
CLEANUP
  }
  trap cleanup EXIT
  python3 - "$root" "$output" "$MADCORE_IOS_SIMULATOR_UDID" "$bundle" <<'RUN'
import pathlib,subprocess,sys
root,output,udid,bundle=sys.argv[1:]
sys.path.insert(0,str(pathlib.Path(root)/'tools'))
from run_ios_host import launch
subprocess.run(['xcrun','simctl','install',udid,str(pathlib.Path(output)/'CompositionHost.app')],check=True,timeout=60)
launch(['xcrun','simctl','launch','--console','--terminate-running-process',udid,bundle],
       str(pathlib.Path(output)/'kotlin-composition.log'),timeout=120,
       pass_marker='MADCORE_KOTLIN_COMPOSITION_PASS',fail_marker='MADCORE_KOTLIN_COMPOSITION_FAIL')
RUN
else
  echo 'Expected build or run mode' >&2
  exit 2
fi
