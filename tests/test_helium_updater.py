"""Exercise release selection and atomic checksum-verified manifest updates."""

import base64
import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "update_helium", Path(__file__).resolve().parents[1] / "scripts/update-helium.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UpdateHeliumTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.sources = Path(temporary.name) / "sources.json"
        self.original = '{"version": "0.1.0", "sources": {}}\n'
        self.sources.write_text(self.original)
        source_patch = patch.object(updater, "SOURCES", self.sources)
        source_patch.start()
        self.addCleanup(source_patch.stop)
        self.payloads = {}
        self.release = {
            "tag_name": "0.2.0",
            "draft": False,
            "prerelease": False,
            "assets": [],
        }
        for system, arch in updater.ARCHITECTURES.items():
            name = f"helium-0.2.0-{arch}_linux.tar.xz"
            url = f"https://github.com/imputnet/helium-linux/releases/download/0.2.0/{name}"
            payload = f"test asset for {system}".encode()
            self.payloads[url] = payload
            self.release["assets"].append(
                {
                    "name": name,
                    "browser_download_url": url,
                    "digest": "sha256:" + hashlib.sha256(payload).hexdigest(),
                }
            )

    def fetch(self, request, **kwargs):
        if isinstance(request, updater.urllib.request.Request):
            return io.BytesIO(json.dumps(self.release).encode())
        return io.BytesIO(self.payloads[request])

    def test_updates_both_architectures_with_downloaded_hashes(self):
        with patch.object(updater.urllib.request, "urlopen", side_effect=self.fetch):
            updater.update()
        manifest = json.loads(self.sources.read_text())
        self.assertEqual(manifest["version"], "0.2.0")
        self.assertEqual(set(manifest["sources"]), set(updater.ARCHITECTURES))
        for source in manifest["sources"].values():
            digest = hashlib.sha256(self.payloads[source["url"]]).digest()
            self.assertEqual(
                source["hash"], "sha256-" + base64.b64encode(digest).decode()
            )

    def test_failed_second_download_preserves_entire_manifest(self):
        second_url = self.release["assets"][1]["browser_download_url"]
        self.payloads[second_url] = b"corrupted download"
        with (
            patch.object(updater.urllib.request, "urlopen", side_effect=self.fetch),
            self.assertRaisesRegex(ValueError, "checksum differs"),
        ):
            updater.update()
        self.assertEqual(self.sources.read_text(), self.original)

    def test_prerelease_is_rejected_without_modifying_manifest(self):
        self.release["prerelease"] = True
        with (
            patch.object(updater.urllib.request, "urlopen", side_effect=self.fetch),
            self.assertRaisesRegex(ValueError, "stable releases"),
        ):
            updater.update()
        self.assertEqual(self.sources.read_text(), self.original)

    def test_unchanged_release_does_not_download_or_rewrite(self):
        with patch.object(updater.urllib.request, "urlopen", side_effect=self.fetch):
            updater.update()
        before = self.sources.stat().st_mtime_ns
        with patch.object(
            updater.urllib.request, "urlopen", side_effect=self.fetch
        ) as fetch:
            updater.update()
        self.assertEqual(fetch.call_count, 1)
        self.assertEqual(self.sources.stat().st_mtime_ns, before)

    def test_missing_architecture_preserves_manifest(self):
        self.release["assets"].pop()
        with (
            patch.object(updater.urllib.request, "urlopen", side_effect=self.fetch),
            self.assertRaises(KeyError),
        ):
            updater.update()
        self.assertEqual(self.sources.read_text(), self.original)


if __name__ == "__main__":
    unittest.main()
