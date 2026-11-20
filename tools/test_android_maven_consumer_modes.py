"""Shell control-flow tests for the Android consumer runner; no Android tools."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).with_name("test_android_maven_consumer.sh")
GRADLE_STUB = """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GRADLE_LOG"
project= upper_repo= core_version=
while (($#)); do
  case "$1" in
    -p) project=$2; shift ;;
    -PupperRepository=*) upper_repo=${1#*=} ;;
    -PmadcoreExpectedCoreVersion=*) core_version=${1#*=} ;;
    :app:assembleDebugAndroidTest) instrument=true ;;
  esac
  shift
done
test "$core_version" = "$EXPECTED_CORE_VERSION"
if [[ "$project" == */upper ]]; then
  for name in alpha beta; do
    publication="$upper_repo/example/madcore/upper/$name/0.1.0/$name-0.1.0"
    mkdir -p "$(dirname "$publication")" "$project/$name/build/outputs/aar"
    printf aar > "$publication.aar"
    printf pom > "$publication.pom"
    printf module > "$publication.module"
    cp "$publication.aar" "$project/$name/build/outputs/aar/$name-release.aar"
  done
else
  test "${instrument:-}" = true
  test ! -e "$project/../upper"
  test ! -e "$project/../thin-aar"
  apk="$project/app/build/outputs/apk"
  mkdir -p "$apk/debug" "$apk/androidTest/debug"
  printf host-apk > "$apk/debug/app-debug.apk"
  if [[ "${MISSING_INSTRUMENTATION:-}" != true ]]; then
    printf test-apk > "$apk/androidTest/debug/app-debug-androidTest.apk"
  fi
fi
"""


class ConsumerModes(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        tools = self.root / "tools"
        tools.mkdir()
        self.runner = tools / RUNNER.name
        shutil.copyfile(RUNNER, self.runner)
        (tools / "check_upper_aars.py").write_text("import sys; assert len(sys.argv) == 2\n")
        (tools / "http_fixture.py").write_text(
            "from pathlib import Path\nPath('fixture-started').touch()\n"
        )
        (self.root / "tmp").mkdir()
        self.repository = self.root / "staging"
        self.repository.mkdir()
        for rel in (
            "android-consumer/settings.gradle", "android-consumer/gradle.properties",
            "android-consumer/app/build.gradle", "android-consumer/app/src/main/empty",
            "android-upper-sdks/build.gradle", "android-upper-sdks/settings.gradle",
            "android-upper-sdks/alpha/build.gradle", "android-upper-sdks/alpha/src/main/empty",
            "android-upper-sdks/beta/build.gradle", "android-upper-sdks/beta/src/main/empty",
        ):
            path = self.root / "examples" / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        gradle = self.root / "gradlew"
        gradle.write_text(GRADLE_STUB)
        gradle.chmod(0o700)

    def run_mode(self, *args, **extra_env):
        env = {**os.environ, "TMPDIR": str(self.root / "tmp"),
               "GRADLE_LOG": str(self.root / "gradle.log"), "GITHUB_ACTIONS": "false",
               "RUNNER_ENVIRONMENT": "", "ANDROID_SERIAL": "",
               "EXPECTED_CORE_VERSION": "0.1.0-SNAPSHOT", **extra_env}
        return subprocess.run(
            ["bash", str(self.runner), str(self.repository), *args],
            env=env, text=True, capture_output=True, timeout=15, check=False,
        )

    def test_build_only_checks_and_hashes_both_apks_without_runtime(self):
        result = self.run_mode("--build-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no device or instrumentation was run", result.stdout)
        self.assertFalse((self.root / "fixture-started").exists())
        lines = (self.root / "gradle.log").read_text().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertIn(":app:verifyPublishedComposition :app:assembleDebug :app:assembleDebugAndroidTest", lines[1])
        self.assertNotIn("connectedDebugAndroidTest", lines[1])
        self.assertNotIn("pixel2api30", lines[1])
        checksum, = (self.root / "tmp").glob("*/apk-sha256.txt")
        self.assertEqual(
            checksum.read_text().splitlines(),
            [hashlib.sha256(b"host-apk").hexdigest() + "  debug/app-debug.apk",
             hashlib.sha256(b"test-apk").hexdigest() + "  androidTest/debug/app-debug-androidTest.apk"],
        )

    def test_fixed_consumer_pin_forwarded_to_upper_and_host_without_fixture(self):
        version = "1.2.3-rehearsal.7"
        result = self.run_mode("--expected-version", version, "--build-only", EXPECTED_CORE_VERSION=version)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "fixture-started").exists())
        lines = (self.root / "gradle.log").read_text().splitlines()
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertIn("-PmadcoreExpectedCoreVersion=" + version, line.split())
            self.assertIn("-Pandroid.builder.sdkDownload=false", line.split())

    def test_invalid_or_ambiguous_pin_rejected_before_gradle(self):
        args = [
            ("--expected-version",), ("--expected-version", "", "--build-only"),
            ("--expected-version", "1.2.+", "--build-only"),
            ("--expected-version", "1.2.3", "--build-only"),
            ("--expected-version", "1.2.3-rehearsal.0"),
            ("--expected-version", "1.2.3-rehearsal.1", "--expected-version", "0.1.0-SNAPSHOT"),
            ("--expected-version", "1.2.3-rehearsal.1", "--connected-api24"),
            ("--build-only", "--connected-api24"),
        ]
        for command in args:
            with self.subTest(command=command):
                self.assertEqual(self.run_mode(*command).returncode, 2)
        self.assertFalse((self.root / "gradle.log").exists())
        self.assertFalse((self.root / "fixture-started").exists())

    def test_missing_instrumentation_fails_without_manifest(self):
        result = self.run_mode("--build-only", MISSING_INSTRUMENTATION="true")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(list((self.root / "tmp").glob("*/apk-sha256.txt")))
        self.assertNotIn("Build only:", result.stdout)

    def test_rejects_unknown_or_empty_mode_and_unapproved_connected_mode(self):
        for args, expected in ((("--external-device",), 2), (("",), 2), (("--connected-api24",), 1)):
            with self.subTest(args=args):
                self.assertEqual(self.run_mode(*args).returncode, expected)
        self.assertFalse((self.root / "gradle.log").exists())


if __name__ == "__main__":
    unittest.main()
