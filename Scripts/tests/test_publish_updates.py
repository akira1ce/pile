import base64
import os
import pathlib
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = pathlib.Path(__file__).resolve().parents[1]
SIGN_TOOL = SCRIPTS.parent / ".build/artifacts/sparkle/Sparkle/bin/sign_update"


@unittest.skipUnless(SIGN_TOOL.is_file(), "Run swift package resolve to install Sparkle's signing tool")
class PublishUpdateTests(unittest.TestCase):
    # Real EdDSA checks; only the external GitHub download is replaced.
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pile-publish-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        for name in ("publish-updates.sh", "validate-appcast.py"):
            shutil.copy2(SCRIPTS / name, scripts / name)
        self.script = scripts / "publish-updates.sh"
        (self.root / "Resources").mkdir()
        (self.root / "Resources/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.2.0"}))
        self.feed = self.root / "build/updates/appcast.xml"
        self.feed.parent.mkdir(parents=True)
        self.dmg = self.root / "build/pile-1.2.0.dmg"
        self.dmg.write_bytes(b"test archive")
        key = self.root / "test-key"
        key.write_text(base64.b64encode(os.urandom(32)).decode())
        key.chmod(0o600)
        signer = [str(SIGN_TOOL), "--ed-key-file", str(key)]
        signature = subprocess.check_output([*signer, "-p", str(self.dmg)], text=True).strip()
        self.feed.write_text(f'''<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>5</sparkle:version><sparkle:shortVersionString>1.2.0</sparkle:shortVersionString>
          <enclosure url="https://github.com/akira1ce/pile/releases/download/1.2.0/pile-1.2.0.dmg" length="12" sparkle:edSignature="{signature}" />
        </item></channel></rss>''')
        subprocess.run([*signer, str(self.feed)], check=True, capture_output=True)
        artifact_bin = self.root / ".build/artifacts/sparkle/Sparkle/bin"
        artifact_bin.mkdir(parents=True)
        wrapper = artifact_bin / "sign_update"
        wrapper.write_text(f"#!/bin/bash\nexec {shlex.join(signer)} \"$@\"\n")
        wrapper.chmod(0o755)
        self.site = self.root / "site/appcast.xml"
        self.site.parent.mkdir()
        self.site.write_text("existing published feed")
        network_bin = self.root / "network-bin"
        network_bin.mkdir()
        curl = network_bin / "curl"
        curl.write_text('''#!/bin/bash
set -euo pipefail
while [[ "$1" != "--output" ]]; do shift; done
output="$2"
case "$PILE_TEST_DOWNLOAD_MODE" in
    unavailable) exit 22 ;;
    mismatch) printf 'wrong archive' > "$output" ;;
    matching) cp "$PILE_TEST_ARCHIVE" "$output" ;;
esac
''')
        curl.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{network_bin}:{os.environ['PATH']}", PILE_TEST_ARCHIVE=str(self.dmg))

    def publish(self, mode):
        return subprocess.run([str(self.script)], env=dict(self.env, PILE_TEST_DOWNLOAD_MODE=mode), capture_output=True, text=True)

    def test_promotes_the_verified_feed_after_a_matching_upload(self):
        result = self.publish("matching")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.site.read_bytes(), self.feed.read_bytes())
        self.assertFalse(list(self.feed.parent.glob(".release-check.*")))

    def test_preserves_the_published_feed_when_the_release_is_unavailable(self):
        self.assertNotEqual(self.publish("unavailable").returncode, 0)
        self.assertEqual(self.site.read_text(), "existing published feed")

    def test_preserves_the_published_feed_when_uploaded_bytes_differ(self):
        self.assertNotEqual(self.publish("mismatch").returncode, 0)
        self.assertEqual(self.site.read_text(), "existing published feed")

    def test_rejects_a_feed_modified_after_signing(self):
        self.feed.write_text(self.feed.read_text().replace("<sparkle:version>5", "<sparkle:version>6"))
        self.assertNotEqual(self.publish("matching").returncode, 0)
        self.assertEqual(self.site.read_text(), "existing published feed")


if __name__ == "__main__":
    unittest.main()
