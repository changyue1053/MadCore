"""Record stable-build evidence in runner temp; print counts only, never upload."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from capture_ios_distribution_evidence import package
from inventory_maven_release_evidence import NOTICE, inventory


ROOT = Path(__file__).resolve().parents[1]


def maven_counts(report):
    archives = report["observedJarAndAarArchives"]
    nested = [jar for artifact in archives for jar in artifact["inspectedNestedJars"]]
    notices = sum(len(artifact["noticeFilenameCandidates"]) for artifact in archives + nested)
    return (f'{report["target"]} Maven evidence: '
            f'{report["declaredMavenEvidence"]["publicationCount"]} POM coordinates, '
            f'{len(report["gradleModuleMetadataFiles"])} Gradle metadata files, '
            f'{len(archives)} outer archives, {len(nested)} nested JARs, '
            f'{notices} hashed notice candidates')


def ios_counts(report):
    slices = report["slices"]
    files = report["packaged_files"]
    notices = sum(NOTICE.match(Path(name).name) is not None and "sha256" in entry
                  for name, entry in files.items())
    return (f'iOS packaging evidence: {len(slices)} static framework slices, '
            f'{sum("sha256" in entry for entry in files.values())} hashed packaged files, '
            f'{notices} hashed notice candidates; supplier and link map not inspected')


def stable_kotlin_version():
    versions = re.findall(
        r"id\s+'org\.jetbrains\.kotlin\.multiplatform'\s+version\s+"
        r"\(ohos\s*\?\s*'[^']+'\s*:\s*'(\d+\.\d+\.\d+)'\s*\)",
        (ROOT / "settings.gradle").read_text(encoding="utf-8"),
    )
    if len(versions) != 1:
        raise ValueError("Stable Kotlin producer declaration was not uniquely recognized")
    return versions[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("jvm", "android", "ios"))
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if not re.fullmatch("[0-9a-f]{40}", revision):
        raise ValueError("Could not identify an exact checkout commit")
    if args.target == "ios":
        code = stable_kotlin_version()
        xcframework = package(args.artifact)
        report = {"source_revision_as_supplied": revision,
                  "kotlin_version_as_supplied": code, "xcframework": xcframework}
        summary = ios_counts(xcframework)
    else:
        manifest = json.loads((ROOT / "SDK-MODULES.json").read_text(encoding="utf-8"))
        report = inventory(args.artifact, manifest, args.target)
        report["checkoutRevision"] = revision
        summary = maven_counts(report)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", delete=False,
                                     dir=os.environ["RUNNER_TEMP"],
                                     prefix="madcore-" + args.target + "-", suffix=".json") as output:
        json.dump(report, output, indent=2, sort_keys=True)
        output.write("\n")
    print(summary)


if __name__ == "__main__":
    main()
