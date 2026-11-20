"""Synthetic Maven staging checks; these do not validate SDK production artifacts."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

from inventory_maven_release_evidence import inventory


MANIFEST = {"group": "test.core", "version": "1", "umbrella": "sdk", "production": ["base"],
            "optInTestOnly": [], "allowedExternal": ["org.jetbrains.kotlin:kotlin-stdlib"]}


def archive(entries):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for path, data in entries:
            output.writestr(path, data)
    return stream.getvalue()


class ReleaseEvidence(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        base_deps = [("org.jetbrains.kotlin", "kotlin-stdlib", "2.2.21")]
        for name, deps in (("sdk", [("test.core", "base", "1")]), ("base", base_deps)):
            pom = self.root / "test/core" / name / "1" / f"{name}-1.pom"
            pom.parent.mkdir(parents=True)
            pom.write_text(
                '<project xmlns="http://maven.apache.org/POM/4.0.0">'
                f"<groupId>test.core</groupId><artifactId>{name}</artifactId><version>1</version>"
                "<dependencies>" + "".join(
                    f"<dependency><groupId>{group}</groupId><artifactId>{artifact}</artifactId>"
                    f"<version>{version}</version></dependency>" for group, artifact, version in deps
                ) + "</dependencies></project>", encoding="utf-8",
            )
        self.staged = self.root / "test/core/base/1"

    def test_aar_and_nested_jar_evidence_are_distinct_from_declared_pom(self):
        nested = archive([("com/mad/core/Core.class", b"class"),
                          ("META-INF/NOTICE.txt", b"nested candidate")])
        extra = archive([("third/party/runtime/Code.class", b"class"),
                         ("META-INF/LICENSE", b"license candidate")])
        artifact = archive([("AndroidManifest.xml", b"manifest"), ("classes.jar", nested),
                            ("META-INF/COPYING", b"copying candidate"), ("libs/runtime.jar", extra),
                            ("jni/arm64-v8a/native.so", b"native")])
        (self.staged / "base-1.aar").write_bytes(artifact)
        (self.staged / "base-1.module").write_text("{}", encoding="ascii")
        report = inventory(self.root, MANIFEST, "android")
        self.assertEqual(report, inventory(self.root, MANIFEST, "android"))
        self.assertEqual(report["declaredMavenEvidence"]["externalDependencies"],
                         ["org.jetbrains.kotlin:kotlin-stdlib:2.2.21"])
        self.assertEqual(len(report["gradleModuleMetadataFiles"]), 1)
        observed, = report["observedJarAndAarArchives"]
        self.assertEqual(observed["sha256"], hashlib.sha256(artifact).hexdigest())
        self.assertEqual(observed["noticeFilenameCandidates"][0]["member"], "META-INF/COPYING")
        self.assertIn("jni/arm64-v8a/native.so",
                      [entry["member"] for entry in observed["embeddedBinaryOrArchiveMembers"]])
        first, second = observed["inspectedNestedJars"]
        self.assertEqual(first["observedClassNamespaces"], {"com.mad.core": 1})
        self.assertEqual(second["observedClassNamespaces"], {"third.party.runtime": 1})
        self.assertEqual(second["noticeFilenameCandidates"][0]["sha256"],
                         hashlib.sha256(b"license candidate").hexdigest())
        self.assertNotIn("license candidate", str(report))

    def test_jvm_reports_multirelease_classes_and_disallows_aar(self):
        binary = archive([("com/mad/core/First.class", b"first"),
                          ("META-INF/versions/21/com/mad/core/First.class", b"jvm21")])
        (self.staged / "base-1.jar").write_bytes(binary)
        observed, = inventory(self.root, MANIFEST, "jvm")["observedJarAndAarArchives"]
        self.assertEqual(observed["observedClassNamespaces"], {"com.mad.core": 2})
        (self.staged / "base-1.aar").write_bytes(archive([("classes.jar", binary)]))
        with self.assertRaisesRegex(ValueError, "Android AAR"):
            inventory(self.root, MANIFEST, "jvm")

    def test_rejects_pathless_archive_symlink_and_no_runtime(self):
        (self.staged / "base-1-sources.jar").write_bytes(archive([("com/mad/core/Api.kt", b"source")]))
        with self.assertRaisesRegex(ValueError, "staging is incomplete"):
            inventory(self.root, MANIFEST, "jvm")
        (self.root / "link").symlink_to(self.staged, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlinks"):
            inventory(self.root, MANIFEST, "jvm")
        (self.root / "link").unlink()
        (self.root / "orphan.jar").write_bytes(archive([("Hidden.class", b"class")]))
        with self.assertRaisesRegex(ValueError, "no corresponding staged POM"):
            inventory(self.root, MANIFEST, "jvm")

    def test_rejects_ambiguous_members_and_corrupt_nested_archive(self):
        path = self.staged / "base-1.aar"
        path.write_bytes(archive([("classes.jar", b"not a zip")]))
        with self.assertRaises(zipfile.BadZipFile):
            inventory(self.root, MANIFEST, "android")
        path.write_bytes(archive([("../NOTICE", b"bad")]))
        with self.assertRaisesRegex(ValueError, "noncanonical"):
            inventory(self.root, MANIFEST, "android")
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            jar = archive([("A.class", b"first"), ("A.class", b"second")])
        path.write_bytes(archive([("classes.jar", jar)]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            inventory(self.root, MANIFEST, "android")


if __name__ == "__main__":
    unittest.main()
