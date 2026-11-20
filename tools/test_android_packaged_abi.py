"""Synthetic archive and comparison gates; never launches Gradle or Android."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import struct
import tempfile
import unittest
import warnings
import zipfile

from compare_android_packaged_abi import modules, prepare, compare


EXPECTED = modules({"production": [f"core-{letter}" for letter in "abcdefgh"],
                    "umbrella": "madcore", "optInTestOnly": ["core-testkit"]})


def zipped(items):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for member, data in items:
            archive.writestr(member, data)
    return output.getvalue()


def class_header(name):
    # Only the JVMS identity prefix needed by preflight, not a runnable class.
    text = name.encode("ascii")
    return (b"\xca\xfe\xba\xbe" + struct.pack(">HHH", 0, 65, 3) + b"\x01"
            + struct.pack(">H", len(text)) + text + b"\x07" + struct.pack(">HH", 1, 1)
            + struct.pack(">H", 2))


def klass(name, *, alias=None):
    return (f"{alias or name}.class", class_header(name))


class Gates(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.left = self.root / "left"
        self.right = self.root / "right"
        self.samples = EXPECTED[:-1]
        for tree in (self.left, self.right):
            for index, module in enumerate(EXPECTED):
                items = [klass(f"example/Core{index}")]
                self.aar(tree, module, items)

    def aar(self, target, module, classes, extra=()):
        path = target / module / 'build/outputs/aar' / f"{module}-release.aar"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(zipped([("AndroidManifest.xml", b"manifest"),
                                 ("classes.jar", zipped(classes)), *extra]))
        return path

    def collect(self, name="input"):
        result = io.StringIO()
        with redirect_stdout(result):
            prepare(self.left, self.right, self.root / name, EXPECTED)
        return result.getvalue().strip()

    def dumps(self, changed=False):
        result = self.root / "dumps"
        for side in ("baseline", "candidate"):
            target = result / side
            target.mkdir(parents=True, exist_ok=True)
            for module in EXPECTED:
                contents = "public class sample/Thing {\n\tpublic fun status ()I\n}\n"
                if changed and module == "core-a" and side == "candidate":
                    contents = contents.replace("()I", "()J")
                (target / f"{module}.api").write_text(contents, encoding="utf-8")
        return result

    def test_inventories_valid_outer_and_included_jars(self):
        for tree in (self.left, self.right):
            external = ("libs/inner.jar", zipped([klass("sample/Inside")]))
            self.aar(tree, "core-a", [klass("sample/Outside")], [external])
        self.assertEqual(self.collect(),
                         "PACKAGED_ANDROID_AAR_INPUTS=9 BASELINE_CLASSES=10 CANDIDATE_CLASSES=10")
        for side in ("baseline", "candidate"):
            self.assertEqual(len(list((self.root / "input" / side / "core-a").glob("*.jar"))), 2)

    def test_missing_debug_only_or_linked_release_is_rejected(self):
        path = self.aar(self.right, "core-a", [klass("sample/Source")])
        debug = path.with_name("core-a-debug.aar")
        path.rename(debug)
        with self.assertRaisesRegex(ValueError, "release AAR"):
            self.collect()
        path.symlink_to(debug)
        with self.assertRaisesRegex(ValueError, "release AAR"):
            self.collect("linked")

    def test_duplicate_and_forged_class_entry_are_rejected(self):
        copies = ("libs/clone.jar", zipped([klass("sample/A")]))
        self.aar(self.left, "core-a", [klass("sample/A")], [copies])
        with self.assertRaisesRegex(ValueError, "Duplicate class"):
            self.collect()
        self.aar(self.left, "core-a", [klass("sample/Correct", alias="some/Wrong")])
        with self.assertRaisesRegex(ValueError, "mismatched"):
            self.collect("forged")
        self.aar(self.left, "core-a", [klass("example/Core1")])
        with self.assertRaisesRegex(ValueError, "Duplicate class"):
            self.collect("between-modules")

    def test_wrong_archive_member_and_unsupported_packaging_fail(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            self.aar(self.left, "core-a", [], [("classes.jar", zipped([]))])
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            self.collect()
        self.aar(self.left, "core-a", [klass("sample/A")], [("../unsafe.txt", b"x")])
        with self.assertRaisesRegex(ValueError, "unsupported ZIP"):
            self.collect("traversal")
        self.aar(self.left, "core-a", [klass("sample/A", alias="META-INF/versions/21/sample/A")])
        with self.assertRaisesRegex(ValueError, "Unsupported JVM class packaging"):
            self.collect("mr")
        self.aar(self.left, "core-a", [klass("sample/A")], [("lint.jar", zipped([]))])
        with self.assertRaisesRegex(ValueError, "only explicitly supported"):
            self.collect("lint")

    def test_changed_included_jar_layout_requires_review(self):
        self.aar(self.right, "core-a", [klass("sample/A")], [("libs/new.jar", zipped([klass("sample/B")]))])
        with self.assertRaisesRegex(ValueError, "layout changed"):
            self.collect()

    def test_comparison_fails_on_changed_descriptor_without_printing_abi(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(compare(self.dumps(changed=True), EXPECTED), 1)
        self.assertEqual(output.getvalue().strip(), "PACKAGED_ANDROID_AAR_ABI_EQUAL=8 CHANGED=1")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(compare(self.dumps(), EXPECTED), 0)
        self.assertEqual(output.getvalue().strip(), "PACKAGED_ANDROID_AAR_ABI_EQUAL=9 CHANGED=0")

    def test_comparison_missing_or_empty_real_module_fails_closed(self):
        path = self.dumps()
        destination = path / "baseline" / "core-a.api"
        destination.write_text("", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "no public ABI"):
            compare(path, EXPECTED)
        destination.unlink()
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            compare(path, EXPECTED)


if __name__ == "__main__":
    unittest.main()
