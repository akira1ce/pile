import base64
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "validate-appcast.py"
SIGNATURE = base64.b64encode(bytes(range(64))).decode()


class AppcastValidationTests(unittest.TestCase):
    # These cases catch publishing a stale/wrong archive or an unsigned update.
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.dmg = self.root / "pile-1.2.0.dmg"
        self.dmg.write_bytes(b"test archive")
        self.feed = self.root / "appcast.xml"

    def validate(self, *, signature=SIGNATURE, length="12", filename="pile-1.2.0.dmg", host="github.com", version="1.2.0", build="5"):
        self.feed.write_text(f'''<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <title>pile &amp; updates</title>
          <sparkle:version>{build}</sparkle:version>
          <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
          <enclosure url="https://{host}/akira1ce/pile/releases/download/1.2.0/{filename}" length="{length}" sparkle:edSignature="{signature}" />
        </item></channel></rss>''')
        return subprocess.run(["python3", str(SCRIPT), str(self.feed), str(self.dmg)], capture_output=True, text=True)

    def test_signed_archive_outputs_its_release_url_and_signature(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"https://github.com/akira1ce/pile/releases/download/1.2.0/pile-1.2.0.dmg\t{SIGNATURE}")

    def test_accepts_a_v_prefixed_github_tag(self):
        self.validate()
        self.feed.write_text(self.feed.read_text().replace("/download/1.2.0/", "/download/v1.2.0/"))
        result = subprocess.run(["python3", str(SCRIPT), str(self.feed), str(self.dmg)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unsigned_and_malformed_signatures(self):
        for signature in ("", "not-a-signature", base64.b64encode(b"short").decode()):
            with self.subTest(signature=signature):
                self.assertNotEqual(self.validate(signature=signature).returncode, 0)

    def test_rejects_a_size_that_does_not_match_the_dmg(self):
        self.assertNotEqual(self.validate(length="11").returncode, 0)

    def test_rejects_a_different_release_asset_or_host(self):
        self.assertNotEqual(self.validate(filename="pile-1.1.2.dmg").returncode, 0)
        self.assertNotEqual(self.validate(host="example.com").returncode, 0)

    def test_rejects_version_metadata_that_disagrees_with_the_archive(self):
        self.assertNotEqual(self.validate(version="1.1.2").returncode, 0)
        self.assertNotEqual(self.validate(build="").returncode, 0)

    def test_rejects_an_empty_feed(self):
        self.feed.write_text("<rss><channel /></rss>")
        result = subprocess.run(["python3", str(SCRIPT), str(self.feed), str(self.dmg)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
