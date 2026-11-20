"""Read-only preflight for the pinned API24 system image; never accepts terms."""
import argparse
import hashlib
from pathlib import Path
import re
from xml.etree import ElementTree


PACKAGE = "system-images;android-24;default;x86_64"
ARCHIVE = "x86_64-24_r08.zip"
LICENSE_ID = "android-sdk-license"
SHA1_LINE = re.compile(rb"[0-9a-f]{40}")


def check(manifest: Path, sdk: Path) -> None:
    payload = manifest.read_bytes()
    print("API24 manifest sha256=" + hashlib.sha256(payload).hexdigest(), flush=True)
    root = ElementTree.fromstring(payload)
    for node in root.iter():
        node.tag = node.tag.rsplit("}", 1)[-1]
    packages = [p for p in root.findall("remotePackage") if p.get("path") == PACKAGE]
    if len(packages) != 1:
        raise ValueError("Pinned API24 package absent or ambiguous in official manifest")
    package = packages[0]
    refs = [element.get("ref") for element in package.findall("uses-license")]
    archives = [element.text for element in package.findall("archives/archive/complete/url")]
    if refs != [LICENSE_ID] or archives != [ARCHIVE]:
        raise ValueError("Pinned API24 package archive or license mapping changed")
    terms = [item for item in root.findall("license") if item.get("id") == LICENSE_ID]
    if len(terms) != 1 or not terms[0].text or len(terms[0]):
        raise ValueError("Pinned API24 license text absent, ambiguous or not plain text")
    fingerprint = hashlib.sha1(terms[0].text.encode("utf-8")).hexdigest()
    accepted = sdk / "licenses" / LICENSE_ID
    try:
        lines = accepted.read_bytes().splitlines()
        present = True
    except FileNotFoundError:
        lines = []
        present = False
    valid_lines = [line for line in lines if SHA1_LINE.fullmatch(line)]
    matched = fingerprint.encode("ascii") in valid_lines
    print(
        f"API24 package={PACKAGE} archive={ARCHIVE} license={LICENSE_ID} "
        f"expected_terms_sha1={fingerprint} acceptance_file_present={present} "
        f"valid_hash_lines={len(valid_lines)} invalid_nonempty_lines="
        f"{sum(bool(line) for line in lines) - len(valid_lines)} exact_match={matched}",
        flush=True,
    )
    if not matched:
        raise ValueError("Exact API24 package license is not already accepted on this runner")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("sdk", type=Path)
    args = parser.parse_args()
    try:
        check(args.manifest, args.sdk)
    except ElementTree.ParseError:
        raise SystemExit("API24 preflight: official package manifest is not valid XML") from None
    except OSError as error:
        raise SystemExit(f"API24 preflight: could not read inputs (errno {error.errno})") from None
    except ValueError as error:
        raise SystemExit(f"API24 preflight: {error}") from None
    print("Pinned API24 image and existing SDK acceptance fingerprint verified")


if __name__ == "__main__":
    main()
