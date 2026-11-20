#!/usr/bin/env bash
# Dedicated minimum-runtime probe. Run only after the normal API30 hosted CI step.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test "${GITHUB_ACTIONS:-}" = true && test "${RUNNER_ENVIRONMENT:-}" = github-hosted || {
  echo 'API24 probe requires a disposable GitHub-hosted runner' >&2
  exit 2
}
test "$(uname -sm)" = "Linux x86_64"
test -r /dev/kvm && test -w /dev/kvm || { echo 'Hosted KVM unavailable' >&2; exit 1; }
if [[ $# != 1 || "$1" != /* || ! -d "$1" ]]; then
  echo 'Expected one absolute path to the staged Android Core Maven repository' >&2
  exit 2
fi
sdk=${ANDROID_HOME:?}
sdkmanager="$sdk/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$sdk/cmdline-tools/latest/bin/avdmanager"
adb="$sdk/platform-tools/adb"
emulator="$sdk/emulator/emulator"
for tool in "$sdkmanager" "$avdmanager" "$adb" "$emulator"; do
  test -x "$tool" || { echo "Existing Android tool unavailable: $(basename "$tool")" >&2; exit 1; }
done

work=$(mktemp -d)
pid=
cleanup() {
  status=$?
  trap - EXIT
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  if [[ "$status" != 0 ]]; then tail -n 60 "$work/emulator.log" 2>/dev/null || true; fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export ANDROID_USER_HOME="$work/user" ANDROID_EMULATOR_HOME="$work/user" ANDROID_AVD_HOME="$work/avd"
mkdir -p "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME"

image='system-images;android-24;default;x86_64'
manifest='https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml'
curl --fail --silent --show-error --proto '=https' --connect-timeout 10 --max-time 45 \
  --max-filesize 4194304 "$manifest" --output "$work/manifest.xml"
# Check the exact official package and the exact terms fingerprint already in
# the runner's SDK, not merely a file with the right license ID. Do not print
# or save terms in build output. sdkmanager itself also checks acceptance.
python3 "$root/tools/check_android_api24_license.py" "$work/manifest.xml" "$sdk"
timeout -k 10s 5m "$sdkmanager" --sdk_root="$sdk" --install --channel=0 "$image" </dev/null
test -s "$sdk/system-images/android-24/default/x86_64/package.xml"

port=5580
serial="emulator-$port"
avd="madcore-api24-${RANDOM}-$$"
devices() { timeout 10 "$adb" devices | awk 'NR > 1 && NF {print $1, $2}'; }
attached=$(devices)
test -z "$attached" || { echo 'Another ADB device is attached; refusing the probe' >&2; exit 1; }
printf 'no\n' | timeout -k 5s 30s "$avdmanager" create avd -n "$avd" -k "$image"
# Fixed unused-on-fresh-runner emulator slot. If unavailable, launch fails;
# the AVD-name and device-set checks prevent any test on an existing emulator.
"$emulator" -avd "$avd" -port "$port" -accel on -gpu swiftshader_indirect -no-window \
  -no-audio -no-boot-anim -no-snapshot > "$work/emulator.log" 2>&1 &
pid=$!
end=$((SECONDS + 240))
while :; do
  kill -0 "$pid" || { echo 'API24 emulator exited during boot' >&2; exit 1; }
  if [[ "$(timeout 5 "$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)" == 1 ]]; then break; fi
  (( SECONDS < end )) || { echo 'API24 emulator boot timeout' >&2; exit 1; }
  sleep 2
done
prop() { timeout 10 "$adb" -s "$serial" shell getprop "$1" | tr -d '\r'; }
test "$(devices)" = "$serial device"
name=$(timeout 10 "$adb" -s "$serial" emu avd name | tr -d '\r')
test "${name%%$'\n'*}" = "$avd"
test "$(prop ro.build.version.sdk)" = 24
test "$(prop ro.product.cpu.abi)" = x86_64
echo "Verified isolated AOSP emulator $serial: Android API 24, x86_64"
ANDROID_SERIAL="$serial" timeout -k 10s 9m bash "$root/tools/test_android_maven_consumer.sh" "$1" --connected-api24
