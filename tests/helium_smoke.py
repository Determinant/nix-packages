"""Run Helium's renderer and JavaScript engine with a disposable profile."""

import argparse
import html
import os
import re
import subprocess
import tempfile
from pathlib import Path


def smoke_test(binary):
    with tempfile.TemporaryDirectory(prefix="helium-smoke-") as directory:
        temporary = Path(directory)
        page = temporary / "test.html"
        # The expected output must be produced by JavaScript, not copied from
        # the source. Also exercise persistent browser storage in this profile.
        page.write_text(
            "<!doctype html><title>Helium smoke test</title><body>"
            "<script>"
            "localStorage.setItem('answer', String(6 * 7));"
            "document.body.textContent = 'renderer-ok:' + localStorage.getItem('answer');"
            "</script></body>"
        )
        command = [
            str(Path(binary).resolve()),
            "--headless",
            "--ozone-platform=headless",
            "--disable-gpu",
            "--disable-software-rasterizer",
            "--disable-background-networking",
            "--disable-component-update",
            "--no-first-run",
            "--no-default-browser-check",
            f"--user-data-dir={temporary / 'profile'}",
            "--dump-dom",
            page.as_uri(),
        ]
        # Leave Chromium's sandbox enabled. Isolate cache writes as well as the
        # browser profile; never run the check against the user's real profile.
        environment = os.environ | {"XDG_CACHE_HOME": str(temporary / "cache")}
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=45,
            env=environment,
            check=False,
        )
        if result.returncode or "<body>renderer-ok:42</body>" not in result.stdout:
            raise RuntimeError(
                f"Helium runtime check failed (exit {result.returncode})\n"
                f"{result.stdout}\n{result.stderr}"
            )
        sandbox = subprocess.run(
            [*command[:-1], "--allow-chrome-scheme-url", "chrome://sandbox"],
            capture_output=True,
            text=True,
            timeout=45,
            env=environment,
            check=False,
        )
        status = " ".join(
            html.unescape(re.sub(r"<[^>]+>", " ", sandbox.stdout)).split()
        )
        required = ["Layer 1 Sandbox Namespace", "Seccomp-BPF sandbox Yes"]
        if sandbox.returncode or not all(value in status for value in required):
            raise RuntimeError(
                f"Helium sandbox check failed (exit {sandbox.returncode})\n"
                f"{status}\n{sandbox.stderr}"
            )
        print(
            "Helium: rendering, JavaScript, storage, and namespace/seccomp sandbox passed"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", help="Path to the packaged bin/helium launcher")
    smoke_test(parser.parse_args().binary)
