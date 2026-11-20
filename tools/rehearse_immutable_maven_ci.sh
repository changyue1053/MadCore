#!/usr/bin/env bash
# Hosted runner adapter: report only allowlisted markers; never print or upload logs.
set -euo pipefail
umask 077
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/madcore-immutable-ci.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$root"
if ! { python3 -B tools/test_immutable_maven_rehearsal.py &&
       python3 -B -O tools/test_immutable_maven_rehearsal.py; } >"$work/unit.log" 2>&1; then
    echo 'MADCORE_IMMUTABLE_JVM_STAGE=unit RESULT=failed'
    exit 1
fi
echo 'MADCORE_IMMUTABLE_JVM_STAGE=unit RESULT=passed'
echo 'MADCORE_IMMUTABLE_JVM_STAGE=rehearsal RESULT=started'
status=0
bash tools/rehearse_immutable_maven.sh jvm 0.1.0-rehearsal.1 >"$work/gradle.log" 2>&1 || status=$?
python3 -B - "$work/gradle.log" "$status" <<'PY'
import re
import sys

log, status = sys.argv[1], int(sys.argv[2])
prepared = complete = False
metadata = classes = None
reason = None
rules = (
    ("baseline drift", "baseline-drift"),
    ("wrong Gradle component", "component-identity"),
    ("Gradle component URL", "component-redirect"),
    ("Gradle available-at", "target-redirect"),
    ("same-module target references", "missing-target-redirect"),
    ("missing or unexpected staged Gradle modules", "module-inventory"),
    ("missing or unexpected staged POM variants", "pom-inventory"),
    ("noncanonical staged Gradle artifact filename", "artifact-filename"),
    ("Gradle logical artifact name", "logical-artifact-name"),
    ("Gradle metadata omits the primary artifact", "primary-artifact"),
    ("Gradle file checksum mismatch", "artifact-checksum"),
    ("Gradle file size or path mismatch", "artifact-size-or-path"),
    ("missing or out-of-stage metadata target", "missing-local-file"),
    ("Gradle internal dependency version", "dependency-version"),
    ("staged publication version", "pom-version"),
    ("Maven metadata", "maven-metadata"),
)
with open(log, encoding="utf-8", errors="replace") as stream:
    for line in stream:
        line = line.rstrip("\r\n")
        if line == "Prepared locked local immutable rehearsal of 66a4789c; no artifact built":
            prepared = True
        matched = re.fullmatch(r"jvm: verified ([1-9][0-9]{0,3}) Gradle metadata files and ([1-9][0-9]{0,3}) staged POMs", line)
        if matched:
            metadata = matched.groups()
        matched = re.fullmatch(r"Unique MadCore JVM classes: ([1-9][0-9]{0,5}); not binary compatibility proof", line)
        if matched:
            classes = matched[1]
        if line == "jvm immutable Maven rehearsal passed (scratch only; no external publication)":
            complete = True
        if line.startswith("Immutable Maven rehearsal: "):
            reason = next((code for text, code in rules if text in line), "metadata-or-overlay")
if prepared:
    print("MADCORE_IMMUTABLE_JVM_STAGE=overlay RESULT=passed")
if metadata:
    modules, poms = metadata
    print(f"MADCORE_IMMUTABLE_JVM_STAGE=staged-metadata RESULT=passed MODULES={modules} POMS={poms}")
if classes:
    print(f"MADCORE_IMMUTABLE_JVM_STAGE=host-classpath RESULT=passed UNIQUE_CORE_CLASSES={classes}")
if status == 0 and prepared and metadata and classes and complete:
    print("MADCORE_IMMUTABLE_JVM_RESULT=passed")
    raise SystemExit(0)
stage = "overlay" if not prepared else ("publication-or-metadata" if not metadata else "host-or-classpath")
if status == 0:
    reason = "missing-evidence-markers"
print(f"MADCORE_IMMUTABLE_JVM_STAGE={stage} RESULT=failed REASON={reason or 'command-failed'}")
print("MADCORE_IMMUTABLE_JVM_RESULT=failed")
raise SystemExit(1)
PY
