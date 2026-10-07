#!/usr/bin/env python3
"""Pin an official stable Helium release and verify both Linux asset hashes."""

import argparse
import base64
import hashlib
import json
import os
import re
import tempfile
import urllib.request
from pathlib import Path

SOURCES = Path(__file__).resolve().parents[1] / "packages" / "helium-sources.json"
RELEASES = "https://api.github.com/repos/imputnet/helium-linux/releases/"
ARCHITECTURES = {"x86_64-linux": "x86_64", "aarch64-linux": "arm64"}


def update(version=None):
    if version is not None and not re.fullmatch(r"\d+(?:\.\d+)+", version):
        raise ValueError("Expected a numeric release version, e.g. 0.18.3.1")
    headers = {"User-Agent": "Determinant-nix-packages-helium-updater"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        RELEASES + (f"tags/{version}" if version else "latest"), headers=headers
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    version = release["tag_name"]
    if release["draft"] or release["prerelease"]:
        raise ValueError("Only published stable releases are accepted")
    if not re.fullmatch(r"\d+(?:\.\d+)+", version):
        raise ValueError(f"Unexpected release tag: {version!r}")

    assets = {asset["name"]: asset for asset in release["assets"]}
    manifest = {"version": version, "sources": {}}
    previous = json.loads(SOURCES.read_text()) if SOURCES.exists() else {}
    for system, arch in ARCHITECTURES.items():
        name = f"helium-{version}-{arch}_linux.tar.xz"
        asset = assets[name]
        url = asset["browser_download_url"]
        expected_url = f"https://github.com/imputnet/helium-linux/releases/download/{version}/{name}"
        if url != expected_url:
            raise ValueError(f"Unexpected asset URL for {name}")
        digest = asset.get("digest")
        if digest and not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError(f"Unexpected digest for {name}: {digest!r}")
        published_hash = (
            "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode()
            if digest
            else None
        )
        old = previous.get("sources", {}).get(system, {})
        if published_hash and old == {"url": url, "hash": published_hash}:
            manifest["sources"][system] = old
            continue

        print(f"Downloading and hashing {name}", flush=True)
        hasher = hashlib.sha256()
        # Do not send the API token to release asset hosts.
        with urllib.request.urlopen(url, timeout=120) as response:
            while chunk := response.read(1024 * 1024):
                hasher.update(chunk)
        actual_hash = "sha256-" + base64.b64encode(hasher.digest()).decode()
        if published_hash and actual_hash != published_hash:
            raise ValueError(
                f"Downloaded checksum differs from GitHub's digest: {name}"
            )
        manifest["sources"][system] = {"url": url, "hash": actual_hash}

    if manifest == previous:
        print(f"Helium {version} is already current")
        return
    # Replace only after both architectures have been verified successfully.
    with tempfile.NamedTemporaryFile(mode="w", dir=SOURCES.parent, delete=False) as f:
        temporary = Path(f.name)
        json.dump(manifest, f, indent=2)
        f.write("\n")
    try:
        temporary.chmod(0o644)
        temporary.replace(SOURCES)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Pinned Helium {version} in {SOURCES}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version", help="Pin a specific stable release instead of latest"
    )
    args = parser.parse_args()
    update(args.version)
