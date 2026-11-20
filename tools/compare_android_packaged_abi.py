"""Local ABI inventory/comparison of selected MadCore release AARs; no runtime claim."""
import argparse
import io
import json
from pathlib import Path
import re
import struct
import zipfile


MAX_JAR = 64 * 1024 * 1024
MAX_CLASS = 2 * 1024 * 1024
MAX_CLASSES_BYTES = 64 * 1024 * 1024
MAX_ZIP_ENTRIES = 10_000
JAR = re.compile(r"libs/[A-Za-z0-9_][A-Za-z0-9_.+-]*\.jar\Z", flags=re.ASCII)
SOURCES = ("baseline", "candidate")


def modules(manifest):
    production = manifest["production"]
    umbrella = manifest["umbrella"]
    names = production + [umbrella]
    if (len(production) != 8 or umbrella != "madcore" or len(set(names)) != len(names)
            or set(names).intersection(manifest["optInTestOnly"])
            or any(not re.fullmatch(r"(?:core-[a-z][a-z0-9-]*|madcore)", part) for part in names)):
        raise ValueError("Expected eight production modules and the distinct MadCore umbrella")
    return names


def entries(archive):
    items = archive.infolist()
    if len(items) > MAX_ZIP_ENTRIES:
        raise ValueError("Too many ZIP members")
    result = {}
    for item in items:
        name = item.filename
        if (item.orig_filename != name or name in result or "\\" in name or (item.flag_bits & 1)
                or any(part in ("", ".", "..") for part in name.rstrip("/").split("/"))
                or (item.external_attr >> 16) & 0o170000 == 0o120000):
            raise ValueError("Ambiguous or unsupported ZIP member")
        if name.rstrip("/") in result or name + "/" in result:
            raise ValueError("Ambiguous ZIP file/directory name")
        result[name] = item
    return result


def internal_class_name(data):
    """Read only the class header and this_class from the JVMS constant pool."""
    reader = io.BytesIO(data)
    take = reader.read
    if take(4) != b"\xca\xfe\xba\xbe":
        raise ValueError("Invalid class signature")
    _, _, count = struct.unpack(">HHH", take(6))
    names, classes = {}, {}
    sizes = {3: 4, 4: 4, 5: 8, 6: 8, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4,
             15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
    index = 1
    while index < count:
        tag = ord(take(1))
        if tag == 1:
            names[index] = take(struct.unpack(">H", take(2))[0])
        elif tag == 7:
            classes[index] = struct.unpack(">H", take(2))[0]
        elif tag in sizes:
            reader.seek(sizes[tag], io.SEEK_CUR)
        else:
            raise ValueError("Unsupported constant pool tag")
        index += 2 if tag in (5, 6) else 1
    _, current = struct.unpack(">HH", take(4))
    return names[classes[current]]


def scan_aar(path, output, seen):
    with zipfile.ZipFile(path) as aar:
        bunch = entries(aar)
        if ("AndroidManifest.xml" not in bunch or bunch["AndroidManifest.xml"].is_dir()
                or not bunch["AndroidManifest.xml"].file_size):
            raise ValueError("Missing Android AAR manifest")
        jars = sorted(name for name in bunch if name.lower().endswith(".jar"))
        if "classes.jar" not in jars or any(name != "classes.jar" and not JAR.fullmatch(name) for name in jars):
            raise ValueError("AAR must contain classes.jar and only explicitly supported libs JARs")
        if sum(bunch[name].file_size for name in jars) > MAX_JAR:
            raise ValueError("AAR nested JAR bytes exceed analysis budget")
        count, class_bytes = 0, 0
        for idx, name in enumerate(jars):
            data = aar.read(bunch[name])
            with zipfile.ZipFile(io.BytesIO(data)) as jar:
                for member, item in entries(jar).items():
                    if not member.lower().endswith(".class") or item.is_dir():
                        continue
                    if (not member.endswith(".class") or member.startswith("META-INF/")
                            or member.rsplit("/", 1)[-1] == "module-info.class"
                            or item.file_size > MAX_CLASS):
                        raise ValueError("Unsupported JVM class packaging")
                    class_bytes += item.file_size
                    if class_bytes > MAX_CLASSES_BYTES:
                        raise ValueError("Expanded classes exceed analysis budget")
                    identity = internal_class_name(jar.read(item))
                    if identity != member[:-6].encode("utf-8") or identity in seen:
                        raise ValueError("Duplicate class identity or mismatched class entry path")
                    seen.add(identity)
                    count += 1
            (output / f"{idx:03}.jar").write_bytes(data)
    if not count:
        raise ValueError("No packaged JVM classes in a production AAR")
    return jars


def prepare(left, right, output, expected):
    if left.resolve() == right.resolve():
        raise ValueError("Provide distinct baseline and candidate producer trees")
    output.mkdir(mode=0o700)
    layout = {}
    total = {}
    for side, root in zip(SOURCES, (left, right)):
        seen = set()
        for module in expected:
            path = root / module / "build/outputs/aar" / f"{module}-release.aar"
            if not path.is_file() or path.is_symlink() or path.resolve() != root.resolve().joinpath(
                    module, "build", "outputs", "aar", f"{module}-release.aar"):
                raise ValueError("Missing or linked expected release AAR")
            into = output / side / module
            into.mkdir(parents=True)
            jars = scan_aar(path, into, seen)
            if side == "baseline":
                layout[module] = jars
            elif jars != layout[module]:
                raise ValueError("Packaged JAR layout changed; explicit review is needed")
        total[side] = len(seen)
    (output / "modules.txt").write_text("\n".join(expected) + "\n", encoding="ascii")
    print(f"PACKAGED_ANDROID_AAR_INPUTS={len(expected)} BASELINE_CLASSES={total['baseline']} "
          f"CANDIDATE_CLASSES={total['candidate']}")


def compare(dumps, expected):
    reports = {}
    for side in SOURCES:
        path = dumps / side
        names = {item.name for item in path.iterdir()}
        if names != {name + ".api" for name in expected}:
            raise ValueError("Incomplete or ambiguous analyzer output")
        api = {}
        for module in expected:
            item = path / (module + ".api")
            if not item.is_file() or item.is_symlink() or item.stat().st_size > MAX_CLASS:
                raise ValueError("Missing, linked or oversized analyzer output")
            value = item.read_text(encoding="utf-8")
            if not value.strip():
                raise ValueError("Analyzer produced no public ABI for a production module")
            api[module] = value
        reports[side] = api
    equal = sum(reports["baseline"][mod] == reports["candidate"][mod] for mod in expected)
    different = len(expected) - equal
    print(f"PACKAGED_ANDROID_AAR_ABI_EQUAL={equal} CHANGED={different}")
    return 1 if different else 0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    subs = p.add_subparsers(dest="stage", required=True)
    prep = subs.add_parser("prepare")
    prep.add_argument("baseline", type=Path)
    prep.add_argument("candidate", type=Path)
    prep.add_argument("output", type=Path)
    diff = subs.add_parser("compare")
    diff.add_argument("dumps", type=Path)
    args = p.parse_args()
    manifest = Path(__file__).resolve().parents[1] / "SDK-MODULES.json"
    try:
        expected = modules(json.loads(manifest.read_text(encoding="utf-8")))
        if args.stage == "prepare":
            prepare(args.baseline, args.candidate, args.output, expected)
            return 0
        return compare(args.dumps, expected)
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, struct.error, zipfile.BadZipFile) as exc:
        p.exit(2, f"Packaged Android AAR inspection failure: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
