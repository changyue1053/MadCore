"""Local JVM/Android Maven inspection. Does not resolve or approve licenses."""
import argparse
from collections import Counter
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

from check_publication_graph import inspect


NOTICE = re.compile(r"^(?:LICEN[CS]ES?|NOTICES?|COPYING|DEPENDENCIES|THIRD[-_. ]?PARTY)(?:$|[-_. ])",
                    re.IGNORECASE)
ARCHIVES = {".jar", ".aar"}
MATERIAL = {".so", ".dex", ".a", ".dll", ".dylib", ".klib", ".jar", ".aar", ".zip"}
MAX_NESTED_JAR = 64 * 1024 * 1024
MAX_NOTICE = 4 * 1024 * 1024


def sha256(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def file_evidence(path):
    with path.open("rb") as source:
        return {"bytes": path.stat().st_size, "sha256": sha256(source)}


def class_namespace(name):
    name = re.sub(r"^META-INF/versions/[0-9]+/", "", name)
    package = name.split("/")[:-1]
    return ".".join(package[:3]) or "<default>"


def inspect_zip(archive, *, inspect_aar_jars=False):
    seen = set()
    classes = Counter()
    material = []
    notices = []
    nested = []
    for entry in sorted(archive.infolist(), key=lambda member: member.filename):
        name = entry.filename
        if (name in seen or name.startswith("/") or "\\" in name
                or any(part in ("", ".", "..") for part in name.rstrip("/").split("/"))):
            raise ValueError(f"Duplicate or noncanonical ZIP member: {name!r}")
        seen.add(name)
        if entry.is_dir():
            continue
        path = PurePosixPath(name)
        suffix = path.suffix.lower()
        if suffix == ".class":
            classes[class_namespace(name)] += 1
        if suffix in MATERIAL:
            material.append({"member": name, "bytes": entry.file_size})
        if NOTICE.match(path.name):
            if entry.file_size > MAX_NOTICE:
                raise ValueError(f"NOTICE candidate exceeds inspection limit: {name!r}")
            with archive.open(entry) as candidate:
                notices.append({"member": name, "bytes": entry.file_size,
                                "sha256": sha256(candidate)})
        if inspect_aar_jars and suffix == ".jar":
            if entry.file_size > MAX_NESTED_JAR:
                raise ValueError(f"AAR nested JAR exceeds inspection limit: {name!r}")
            contents = archive.read(entry)
            with zipfile.ZipFile(io.BytesIO(contents)) as jar:
                nested.append({"member": name, "bytes": len(contents),
                               "sha256": hashlib.sha256(contents).hexdigest(),
                               **inspect_zip(jar)})
    return {"classCount": sum(classes.values()), "observedClassNamespaces": dict(sorted(classes.items())),
            "embeddedBinaryOrArchiveMembers": material, "noticeFilenameCandidates": notices,
            "inspectedNestedJars": nested}


def inventory(repository, manifest, target):
    if target not in {"android", "jvm"}:
        raise ValueError("Select one JVM or Android staged repository")
    if not repository.is_dir() or repository.is_symlink():
        raise ValueError("Staged repository must be a real directory")
    paths = sorted(repository.rglob("*"))
    if any(path.is_symlink() for path in paths):
        raise ValueError("Staged repository must not contain symlinks")
    graph = inspect(repository, manifest)
    pom_stems = {}
    for relative_pom in graph["pomSha256"]:
        path = repository / relative_pom
        pom_stems.setdefault(path.parent, set()).add(path.stem)
    archives = []
    gradle_metadata = []
    for path in paths:
        if not path.is_file() or path.suffix.lower() not in (ARCHIVES | {".module"}):
            continue
        relative_path = path.relative_to(repository).as_posix()
        matches = [stem for stem in pom_stems.get(path.parent, ())
                   if path.stem == stem or path.stem.startswith(stem + "-")]
        if not matches:
            raise ValueError("Archive or Gradle metadata has no corresponding staged POM: " + relative_path)
        stem = max(matches, key=len)
        classifier = path.stem[len(stem) + 1:] if path.stem != stem else None
        evidence = {"path": relative_path, "classifier": classifier, **file_evidence(path)}
        if path.suffix.lower() == ".module":
            gradle_metadata.append(evidence)
            continue
        with zipfile.ZipFile(path) as archive:
            content = inspect_zip(archive, inspect_aar_jars=path.suffix.lower() == ".aar")
        archives.append({**evidence, **content})
    required_suffix = ".aar" if target == "android" else ".jar"
    if not any(item["classifier"] is None and Path(item["path"]).suffix == required_suffix
               and item["classCount"] + sum(jar["classCount"] for jar in item["inspectedNestedJars"]) > 0
               for item in archives):
        raise ValueError(f"No {target} {required_suffix} containing JVM classes; staging is incomplete")
    if target == "jvm" and any(Path(item["path"]).suffix.lower() == ".aar" for item in archives):
        raise ValueError("An Android AAR was found in the JVM staging repository")
    return {"schemaVersion": 1, "target": target,
            "scope": "Local staging evidence only; not an SBOM, compiler attribution or release approval",
            "declaredMavenEvidence": graph,
            "gradleModuleMetadataFiles": gradle_metadata,
            "observedJarAndAarArchives": archives}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--target", choices=("jvm", "android"), required=True)
    args = parser.parse_args()
    manifest_path = Path(__file__).resolve().parents[1] / "SDK-MODULES.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        report = inventory(args.repository, manifest, args.target)
    except (ValueError, OSError, RuntimeError, ET.ParseError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Maven inventory failed: {error}\n")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
