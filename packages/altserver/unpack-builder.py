"""Unpack the pinned Docker archive as an unprivileged compiler sysroot."""
import json
import os
import posixpath
import shutil
import sys
import tarfile
from pathlib import Path

archive, destination = sys.argv[1:]
root = Path(destination).resolve()
root.mkdir()
with tarfile.open(archive) as image:
    manifest = json.load(image.extractfile("manifest.json"))
    for layer in manifest[0]["Layers"]:
        # Docker-archive layers can be read directly without materializing
        # a second copy of the compiler image.
        with image.extractfile(layer) as stream, tarfile.open(fileobj=stream) as contents:
            members = contents.getmembers()
            for member in members:
                name = Path(member.name)
                if name.name.startswith(".wh."):
                    target = root / name.parent
                    if name.name != ".wh..wh..opq":
                        target /= name.name[4:]
                    target = Path(os.path.abspath(target))
                    if not target.is_relative_to(root) or not target.parent.resolve().is_relative_to(root):
                        raise ValueError(f"Whiteout outside sysroot: {name}")
                    if name.name == ".wh..wh..opq":
                        if target.is_symlink():
                            raise ValueError(f"Opaque whiteout on symlink: {name}")
                        for child in target.iterdir() if target.exists() else []:
                            if child.is_dir() and not child.is_symlink():
                                shutil.rmtree(child)
                            else:
                                child.unlink()
                    elif target.is_dir() and not target.is_symlink():
                        shutil.rmtree(target)
                    else:
                        target.unlink(missing_ok=True)
            def sysroot_filter(member, dest):
                if member.issym() and member.linkname.startswith("/"):
                    member = member.replace(linkname=posixpath.relpath(
                        member.linkname, "/" + posixpath.dirname(member.name).lstrip("/")))
                elif member.islnk() and member.linkname.startswith("/"):
                    member = member.replace(linkname=member.linkname.lstrip("/"))
                return tarfile.data_filter(member, dest)

            # The data filter rejects escaping paths/links and strips ownership,
            # setuid/setgid bits. Device nodes are supplied at build time.
            for member in members:
                if Path(member.name).name.startswith(".wh.") or member.isdev():
                    continue
                filtered = sysroot_filter(member, str(root))
                target = root / filtered.name
                # An upper-layer regular file must replace a lower-layer symlink,
                # not overwrite its target (e.g. a BusyBox applet).
                if target.is_symlink() or (target.exists() and not
                        (target.is_dir() and filtered.isdir())):
                    if target.is_dir() and not target.is_symlink():
                        shutil.rmtree(target)
                    else:
                        target.unlink()
                contents.extract(filtered, root, filter=sysroot_filter)
