import hashlib
import json
import os
import pathlib
import plistlib
import runpy
import subprocess
import tempfile
import unittest
import zipfile
import base64


project = pathlib.Path(__file__).resolve().parents[1]
release = runpy.run_path(str(project / "scripts/prepare-release.py"))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kaze-release-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.source = self.root / "project"
        (self.source / "src").mkdir(parents=True)
        (self.source / "docs").mkdir()
        self.info = plistlib.dumps({"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "15",
                                   "LSMinimumSystemVersion": "13.0", "SURequireSignedFeed": True})
        (self.source / "src/Info.plist").write_bytes(self.info)
        self.notes = self.source / "docs/RELEASE_NOTES.md"
        self.notes.write_text("# Kaze 1.0.0\n\nNotas de ejemplo.\n")
        self.artifacts = self.root / "artifacts"
        self.output = self.root / "release assets"
        for architecture in ("arm64", "x86_64"):
            folder = self.artifacts / f"kaze-{architecture}"
            folder.mkdir(parents=True)
            for extension in ("dmg", "zip"):
                (folder / f"Kaze-Mac-{architecture}.{extension}").write_bytes(architecture.encode())
            self.write_source(architecture)
            self.write_feed(architecture)
            self.hash_artifact(architecture)

    def write_feed(self, architecture, version="15", url_architecture=None):
        folder = self.artifacts / f"kaze-{architecture}"
        signature = base64.b64encode(bytes(64)).decode()
        (folder / f"appcast-{architecture}.xml").write_text(f'''<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>{version}</sparkle:version><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="https://github.com/Sora-Agency/kaze/releases/download/v1.0.0/Kaze-Mac-{url_architecture or architecture}.dmg"
length="{len(architecture)}" sparkle:edSignature="{signature}" /></item></channel></rss>
<!-- sparkle-signatures:
edSignature: {signature}
length: 100
-->''')

    def write_source(self, architecture, text=b"Kaze", info=None):
        path = self.artifacts / f"kaze-{architecture}/Kaze-Source.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name, data in [("src/Info.plist", info or self.info), ("README.md", text)]:
                entry = zipfile.ZipInfo("Kaze-Source/" + name,
                    (2026, 10, 11, 12 if architecture == "arm64" else 13, 0, 0))
                archive.writestr(entry, data)

    def hash_artifact(self, architecture):
        folder = self.artifacts / f"kaze-{architecture}"
        names = [f"Kaze-Mac-{architecture}.dmg", f"Kaze-Mac-{architecture}.zip", "Kaze-Source.zip", f"appcast-{architecture}.xml"]
        (folder / f"Kaze-SHA256-{architecture}.txt").write_text("".join(
            hashlib.sha256((folder / name).read_bytes()).hexdigest() + "  " + name + "\n" for name in names))

    def prepare(self):
        release["prepare_release"](self.source, "v1.0.0", self.artifacts, self.output)

    def test_assets_and_all_manifests(self):
        self.assertNotEqual((self.artifacts / "kaze-arm64/Kaze-Source.zip").read_bytes(),
                            (self.artifacts / "kaze-x86_64/Kaze-Source.zip").read_bytes())
        self.prepare()
        self.assertEqual(len(list(self.output.iterdir())), 10)
        for manifest in ("SHA256SUMS", "Kaze-SHA256-arm64.txt", "Kaze-SHA256-x86_64.txt"):
            for line in (self.output / manifest).read_text().splitlines():
                digest, name = line.split("  ")
                self.assertEqual(digest, hashlib.sha256((self.output / name).read_bytes()).hexdigest())

    def test_tag_and_notes_match_version(self):
        for tag in ("v1.0.1", "1.0.0", "v1.0.0;echo unsafe", "v01.0.0"):
            with self.assertRaises(ValueError):
                release["validate_version"](self.source, tag)
        self.notes.write_text("# Kaze 0.9.9\n")
        with self.assertRaises(ValueError):
            self.prepare()

    def test_corrupt_asset_rejected(self):
        (self.artifacts / "kaze-x86_64/Kaze-Mac-x86_64.dmg").write_bytes(b"damaged")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_missing_architecture_rejected(self):
        (self.artifacts / "kaze-x86_64/Kaze-SHA256-x86_64.txt").unlink()
        with self.assertRaises(OSError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_different_sources_rejected(self):
        self.write_source("x86_64", text=b"Other commit")
        self.hash_artifact("x86_64")
        with self.assertRaises(ValueError):
            self.prepare()

    def test_wrong_source_version_rejected(self):
        wrong = plistlib.dumps({"CFBundleShortVersionString": "0.9.9"})
        for architecture in ("arm64", "x86_64"):
            self.write_source(architecture, info=wrong)
            self.hash_artifact(architecture)
        with self.assertRaises(ValueError):
            self.prepare()

    def test_wrong_update_architecture_rejected(self):
        self.write_feed("x86_64", url_architecture="arm64")
        self.hash_artifact("x86_64")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_wrong_update_build_rejected(self):
        self.write_feed("arm64", version="14")
        self.hash_artifact("arm64")
        with self.assertRaises(ValueError):
            self.prepare()

    def test_unsigned_feed_rejected(self):
        path = self.artifacts / "kaze-arm64/appcast-arm64.xml"
        path.write_text(path.read_text().replace("sparkle:edSignature=", "unsigned="))
        self.hash_artifact("arm64")
        with self.assertRaises(ValueError):
            self.prepare()

    def test_missing_update_feed_rejected(self):
        (self.artifacts / "kaze-arm64/appcast-arm64.xml").unlink()
        with self.assertRaises(OSError):
            self.prepare()

    def fake_cli(self, state):
        self.prepare()
        self.cli_log = self.root / "calls.jsonl"
        self.cli_state = self.root / "state"
        self.cli_state.write_text(state)
        executable = self.root / "gh"
        executable.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['KAZE_TEST_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
state = pathlib.Path(os.environ['KAZE_TEST_STATE'])
if args[:2] == ['release', 'view']:
    current = state.read_text()
    if current in ('new', 'partial'): sys.exit(1)
    print('true' if current == 'draft' else 'false')
elif args[:2] == ['release', 'create']:
    previous = state.read_text()
    state.write_text('draft')
    if previous == 'partial': sys.exit(1)
elif args[:2] != ['release', 'upload']:
    sys.exit(2)
""")
        executable.chmod(0o755)

    def create_draft(self):
        environment = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ["PATH"],
            GH_REPO="Sora-Agency/kaze", KAZE_RELEASE_COMMIT="a" * 40,
            KAZE_TEST_LOG=str(self.cli_log), KAZE_TEST_STATE=str(self.cli_state))
        return subprocess.run(["bash", str(project / "scripts/create-draft-release.sh"),
            "v1.0.0", str(self.output), str(self.notes)], env=environment, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.cli_log.read_text().splitlines()]

    def test_new_release_is_always_a_draft(self):
        self.fake_cli("new")
        self.assertEqual(self.create_draft().returncode, 0)
        command = self.calls()[-1]
        self.assertEqual(command[:3], ["release", "create", "v1.0.0"])
        self.assertIn("--draft", command)
        self.assertIn("--verify-tag", command)
        self.assertEqual(command[command.index("--target") + 1], "a" * 40)
        for file in self.output.iterdir():
            self.assertIn(str(file), command)

    def test_retry_completes_draft_without_editing_notes(self):
        self.fake_cli("partial")
        self.assertNotEqual(self.create_draft().returncode, 0)
        self.assertEqual(self.create_draft().returncode, 0)
        command = self.calls()[-1]
        self.assertEqual(command[:3], ["release", "upload", "v1.0.0"])
        self.assertIn("--clobber", command)
        self.assertNotIn("edit", command)

    def test_published_release_is_untouched(self):
        self.fake_cli("published")
        self.assertNotEqual(self.create_draft().returncode, 0)
        self.assertEqual(len(self.calls()), 1)


if __name__ == "__main__":
    unittest.main()
