#!/usr/bin/env bash
# Opt-in JVM integration check. Run from a commit containing this tool.
set -euo pipefail
root=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/madcore-version-test.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/source"
git -C "$root" archive HEAD | tar -xf - -C "$work/source"
cd "$work/source"
test -f tools/test_sdk_version_generation.sh
export GRADLE_USER_HOME="$work/gradle-home"
mkdir "$GRADLE_USER_HOME"
printf '%s\n' 'org.gradle.java.installations.auto-download=false' > "$GRADLE_USER_HOME/gradle.properties"
cat > "$work/VerifyMadCoreVersion.java" <<'JAVA'
import com.mad.core.MadCoreInfo;
public class VerifyMadCoreVersion {
    public static void main(String[] args) {
        if (!args[0].equals(MadCoreInfo.INSTANCE.getVersion())) {
            throw new AssertionError("Packaged runtime identity disagrees with the test input");
        }
    }
}
JAVA
cat > "$work/expected-api.txt" <<'API'
Compiled from "MadCoreInfo.kt"
public final class com.mad.core.MadCoreInfo {
  public static final com.mad.core.MadCoreInfo INSTANCE;
    descriptor: Lcom/mad/core/MadCoreInfo;
  public final java.lang.String getVersion();
    descriptor: ()Ljava/lang/String;
}
API
verify_version() {
    local expected=$1
    local stage=build/staging-repository/jvm
    ./gradlew --no-daemon -Pmadcore.target=jvm publishAllPublicationsToStagingRepository
    python3 -B tools/check_publication_graph.py "$stage"
    local staged="$stage/com/mad/core/madcore-jvm/$expected"
    local artifacts=("$staged"/madcore-jvm-*.jar)
    local primary=() sources=()
    local jar
    for jar in "${artifacts[@]}"; do
        [[ -f "$jar" ]] || continue
        case "$jar" in
            *-sources.jar) sources+=("$jar") ;;
            *-javadoc.jar) ;;
            *) primary+=("$jar") ;;
        esac
    done
    test "${#primary[@]}" -eq 1
    test "${#sources[@]}" -eq 1
    local generated=madcore/build/generated/madcoreInfo/commonMain/com/mad/core/MadCoreInfo.kt
    python3 -B - "$expected" "${primary[0]}" "${sources[0]}" "$generated" <<'PYTHON'
import hashlib
from pathlib import Path
import sys
from zipfile import ZipFile

version, binary_jar, sources_jar, generated = sys.argv[1:]
source = Path(generated).read_bytes()
if version == '0.1.0-SNAPSHOT':
    # Pre-change 5145f4f's exact MadCoreInfo.kt bytes, including line endings.
    blob = f'blob {len(source)}\0'.encode() + source
    if hashlib.sha1(blob).hexdigest() != 'b78e0ed64549d0cf27a624b6e51b806f93e1fd9c':
        raise SystemExit('Default generated Kotlin source differs from the baseline blob')
if f'val version: String = "{version}"'.encode() not in source:
    raise SystemExit('Generated Kotlin source disagrees with the test version')
with ZipFile(binary_jar) as archive:
    classes = sorted(name for name in archive.namelist() if name.endswith('.class'))
    if classes != ['com/mad/core/MadCoreInfo.class']:
        raise SystemExit('Unexpected JVM umbrella class inventory or helper holder')
with ZipFile(sources_jar) as archive:
    kotlin = sorted(name for name in archive.namelist() if name.endswith('.kt'))
    if (len(kotlin) != 1 or not kotlin[0].endswith('com/mad/core/MadCoreInfo.kt')
            or archive.read(kotlin[0]) != source
            or any(name.endswith('.kt.template') for name in archive.namelist())):
        raise SystemExit('JVM sources archive must contain only the exact generated Kotlin source')
PYTHON
    javap -classpath "${primary[0]}" -public -s com.mad.core.MadCoreInfo > "$work/actual-api.txt"
    diff -u "$work/expected-api.txt" "$work/actual-api.txt"
    java --class-path "${primary[0]}" "$work/VerifyMadCoreVersion.java" "$expected"
}
# Independently supplied expectations; never derive them from the exported code.
verify_version 0.1.0-SNAPSHOT
# Move only output repository. Keep task state and generated/compiled inputs warm.
mv build/staging-repository/jvm "$work/first-stage"
python3 - <<'PYTHON'
import json
from pathlib import Path
path = Path("SDK-MODULES.json")
manifest = json.loads(path.read_text())
if manifest["version"] != "0.1.0-SNAPSHOT":
    raise SystemExit("Unexpected default in JVM version fixture")
manifest["version"] = "0.1.0-rehearsal.1"
path.write_text(json.dumps(manifest, indent=2) + "\n")
PYTHON
verify_version 0.1.0-rehearsal.1
echo 'JVM producer version authority verified for default and warm rebuild'
