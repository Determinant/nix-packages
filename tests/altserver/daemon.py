#!/usr/bin/env python3
"""Offline framing/cleanup smoke test; never connects to Apple or a device."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import time


def receive(sock, size):
    result = b""
    while len(result) < size:
        data = sock.recv(size - len(result))
        if not data:
            raise AssertionError("truncated response")
        result += data
    return result


def listener(pid):
    targets = {os.readlink(fd) for fd in Path(f"/proc/{pid}/fd").iterdir()}
    for line in Path(f"/proc/{pid}/net/tcp").read_text().splitlines()[1:]:
        fields = line.split()
        if fields[3] == "0A" and f"socket:[{fields[9]}]" in targets:
            return int(fields[1].split(":")[1], 16)


executable = str(Path(sys.argv[1]).resolve())

with tempfile.TemporaryDirectory(prefix="altserver-smoke-") as directory:
    root = Path(directory)
    # Disable advertisement and device subscriptions. Tests use only loopback.
    stub = root / "python3"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
               ALTSERVER_NO_SUBSCRIBE="1", HOME=str(root), XDG_CONFIG_HOME=str(root))
    with (root / "server.log").open("w+") as log:
        process = subprocess.Popen([executable], env=env, cwd=root,
                                   stdout=log, stderr=log, start_new_session=True)
        try:
            port = None
            for _ in range(100):
                assert process.poll() is None, "server exited"
                port = listener(process.pid)
                if port:
                    break
                time.sleep(0.05)
            assert port is not None, "server never listened"
            initial = len(list(Path(f"/proc/{process.pid}/fd").iterdir()))
            for _ in range(20):
                with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
                    sock.sendall(b"\x04\x00") # disconnect halfway through header
            for payload in [json.dumps({"version": 1, "identifier": "OfflineRegressionRequest"}).encode(), b"{"]:
                with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
                    frame = struct.pack("<i", len(payload)) + payload
                    for byte in frame:
                        sock.sendall(bytes([byte]))
                    size = struct.unpack("<i", receive(sock, 4))[0]
                    response = json.loads(receive(sock, size))
                    assert response["identifier"] == "ErrorResponse", response
            with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
                sock.sendall(struct.pack("<i", -1))
                size = struct.unpack("<i", receive(sock, 4))[0]
                assert json.loads(receive(sock, size))["identifier"] == "ErrorResponse"
            time.sleep(2)
            final = len(list(Path(f"/proc/{process.pid}/fd").iterdir()))
            assert final <= initial + 3, (initial, final)
            assert process.poll() is None
            print(f"Daemon smoke test passed: fragmented requests, truncated peers, invalid JSON/length; descriptors {initial} -> {final}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            if process.returncode not in (0, -15):
                log.seek(0)
                print(log.read()[-3000:])
