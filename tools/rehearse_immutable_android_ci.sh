#!/usr/bin/env bash
# Hosted runner adapter. Build-only; never print/upload raw logs or private APKs.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-immutable-android.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$root"
version=0.1.0-rehearsal.1
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted ||
      "$(uname -sm)" != "Linux x86_64" || -z "$sdk" ||
      ! -s "$sdk/platforms/android-36/android.jar" ||
      ! -x "$sdk/build-tools/35.0.0/zipalign" ||
      ! -x "$sdk/build-tools/35.0.0/apksigner" ]]; then
    echo 'MADCORE_IMMUTABLE_ANDROID_STAGE=sdk RESULT=failed REASON=preinstalled-sdk-required'
    exit 1
fi
if [[ -n "${ANDROID_SDK_ROOT:-}" && "$(realpath -e -- "$sdk" 2>/dev/null)" != "$(realpath -e -- "$ANDROID_SDK_ROOT" 2>/dev/null)" ]]; then
    echo 'MADCORE_IMMUTABLE_ANDROID_STAGE=sdk RESULT=failed REASON=conflicting-sdk-roots'
    exit 1
fi
export ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="$sdk" TMPDIR="$work"
echo 'MADCORE_IMMUTABLE_ANDROID_STAGE=sdk RESULT=passed'
echo 'MADCORE_IMMUTABLE_ANDROID_STAGE=rehearsal RESULT=started'
status=0
bash tools/rehearse_immutable_maven.sh android "$version" >"$work/gradle.log" 2>&1 || status=$?
python3 -B - "$work/gradle.log" "$status" "$version" <<'PY'
from collections import Counter
import re
import sys

log, status, version = sys.argv[1], int(sys.argv[2]), sys.argv[3]
counts = Counter()
metadata = None
reason = None
classpaths = ('debugCompileClasspath', 'debugRuntimeClasspath',
              'releaseCompileClasspath', 'releaseRuntimeClasspath')
expected = {
    'Prepared locked local immutable rehearsal of 66a4789c; no artifact built': 'overlay',
    'Build only: no device or instrumentation was run.': 'apk',
    'Alpha/Beta Maven metadata request only the expected Core coordinate': 'uppers',
    'android immutable Maven rehearsal passed (scratch only; no external publication)': 'complete',
    **{name + ': one Android Core version through two published upper AARs': name for name in classpaths},
}
rules = (
    ('baseline drift', 'baseline-drift'),
    ('wrong Gradle component', 'component-identity'),
    ('Gradle component URL', 'component-redirect'),
    ('Gradle available-at', 'target-redirect'),
    ('same-module target references', 'missing-target-redirect'),
    ('missing or unexpected staged Gradle modules', 'module-inventory'),
    ('missing or unexpected staged POM variants', 'pom-inventory'),
    ('Gradle logical artifact name', 'logical-artifact-name'),
    ('Gradle metadata omits the primary artifact', 'primary-artifact'),
    ('Gradle file checksum mismatch', 'artifact-checksum'),
    ('Gradle file size or path mismatch', 'artifact-size-or-path'),
    ('Gradle internal dependency version', 'dependency-version'),
    ('staged publication version', 'pom-version'),
    ('published Core POM edge', 'upper-pom-edge'),
    ('upper Android AAR missing', 'upper-aar'),
    ('Maven metadata', 'maven-metadata'),
)
with open(log, encoding='utf-8', errors='replace') as stream:
    for line in stream:
        line = line.rstrip('\r\n')
        if line in expected:
            counts[expected[line]] += 1
        match = re.fullmatch(
            r'android: verified ([1-9][0-9]{0,3}) Gradle metadata files and ([1-9][0-9]{0,3}) staged POMs',
            line,
        )
        if match:
            metadata = match.groups()
            counts['metadata'] += 1
        if line.startswith('Immutable Maven rehearsal: '):
            reason = next((code for phrase, code in rules if phrase in line), 'metadata-or-overlay')
        elif 'must contain one Android AAR per production Core module:' in line:
            reason = 'consumer-selected-core'
        elif 'must contain the two published upper AARs:' in line:
            reason = 'consumer-selected-uppers'
        elif 'Expected only the two upper Maven dependencies,' in line:
            reason = 'consumer-direct-dependencies'
if counts['overlay'] == 1:
    print('MADCORE_IMMUTABLE_ANDROID_STAGE=overlay RESULT=passed')
if counts['metadata'] == 1:
    modules, poms = metadata
    print(f'MADCORE_IMMUTABLE_ANDROID_STAGE=staged-metadata RESULT=passed MODULES={modules} POMS={poms}')
# The locked Gradle task prints each marker only after checking one AAR per
# production module and the exact rewritten version on that configuration.
if all(counts[name] == 1 for name in classpaths):
    print(f'MADCORE_IMMUTABLE_ANDROID_STAGE=consumer-classpaths RESULT=passed COUNT=4 CORE_VERSION={version}')
if counts['apk'] == 1:
    print('MADCORE_IMMUTABLE_ANDROID_STAGE=apk RESULT=passed COUNT=2 DEVICE_RUN=false')
if counts['uppers'] == 1:
    print('MADCORE_IMMUTABLE_ANDROID_STAGE=upper-metadata RESULT=passed COUNT=2')
necessary = ('overlay', 'metadata', *classpaths, 'apk', 'uppers', 'complete')
if status == 0 and not reason and all(counts[k] == 1 for k in necessary):
    print('MADCORE_IMMUTABLE_ANDROID_RESULT=passed')
    raise SystemExit(0)
stages = (('overlay', ('overlay',)), ('publication-or-metadata', ('metadata',)),
          ('consumer-or-apk', (*classpaths, 'apk')), ('upper-metadata', ('uppers',)),
          ('completion', ('complete',)))
stage = next((label for label, keys in stages if any(counts[key] != 1 for key in keys)), 'completion')
if status == 0 and not reason:
    reason = 'missing-or-duplicate-evidence'
print(f'MADCORE_IMMUTABLE_ANDROID_STAGE={stage} RESULT=failed REASON={reason or "command-failed"}')
print('MADCORE_IMMUTABLE_ANDROID_RESULT=failed')
raise SystemExit(1)
PY
