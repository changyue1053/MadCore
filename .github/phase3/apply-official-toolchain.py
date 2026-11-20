"""Apply the candidate pins only in the Phase 3 disposable checkout."""
from pathlib import Path

KOTLIN_PINS = (
    "settings.gradle",
    "examples/android-consumer/app/build.gradle",
    "examples/android-upper-sdks/build.gradle",
    "examples/ios-kotlin-composition/producers/build.gradle",
    "examples/ios-kotlin-composition/umbrella/build.gradle",
    "examples/jvm-consumer/build.gradle",
)
WRAPPER = "gradle/wrapper/gradle-wrapper.properties"
# https://gradle.org/release-checksums/ (9.3.0 binary-only ZIP)
CHECKSUM = b"0d585f69da091fc5b2beced877feab55a3064d43b8a1d46aeb07996b0915e0e0"


def replacement(path, old, new):
    original = path.read_bytes()
    if original.count(old) != 1 or new in original:
        raise SystemExit(f"Unexpected baseline or repeated overlay: {path}")
    return original.replace(old, new)


def main():
    root = Path(__file__).resolve().parents[2]
    changes = {
        root / name: replacement(root / name, b"'2.2.21'", b"'2.3.21'")
        for name in KOTLIN_PINS
    }
    wrapper = root / WRAPPER
    if b"distributionSha256Sum" in wrapper.read_bytes():
        raise SystemExit("Baseline wrapper already has a checksum; review the overlay")
    changes[wrapper] = replacement(
        wrapper,
        b"gradle-9.4.1-bin.zip\n",
        b"gradle-9.3.0-bin.zip\ndistributionSha256Sum=" + CHECKSUM + b"\n",
    )
    for path, content in changes.items():
        path.write_bytes(content)
    print("Official-target candidate: Kotlin 2.3.21, Gradle 9.3.0; AGP unchanged (8.13.2)")


if __name__ == "__main__":
    main()
