{
  lib,
  stdenvNoCC,
  fetchgit,
  dockerTools,
  runCommand,
  proot,
  makeWrapper,
  bubblewrap,
  cacert,
  python3,
  avahi-compat,
}:
let
  # The upstream musl toolchain includes corecrypto and the matching LibreSSL
  # and cpprestsdk. Pin it by digest; Docker is not needed to build or run.
  builderImage = dockerTools.pullImage {
    imageName = "ghcr.io/nyamisty/altserver_builder_alpine_amd64";
    imageDigest = "sha256:b96e411d23a2c8472942990b72fb902f7f08ce290889d40e46ce80ccb1b77dd7";
    hash = "sha256-OLtLN4dnX7G24vE+boy/UY1GhNM5b+BLGLimt0x06BU=";
    finalImageTag = "latest";
    os = "linux";
    arch = "amd64";
  };
  builderRoot = runCommand "altserver-build-root" { } ''
    ${python3}/bin/python3 ${./altserver/unpack-builder.py} ${builderImage} "$out"
  '';
in
stdenvNoCC.mkDerivation rec {
  pname = "altserver-linux-ng";
  version = "2026-11-05-r1";

  src = fetchgit {
    url = "https://github.com/jaakkopalvaila/AltServer-Linux";
    rev = "8ab21362e47e7d24e18f54ad8a39a4400cf97ebe";
    hash = "sha256-hQxUbgrXMO6UONoY49itnTiFmqqeJ6homs9miDRlI+4=";
    fetchSubmodules = true;
  };

  # The Windows sources contain mixed CRLF/LF. Normalize before applying the
  # reviewed source patch, and leave the source rewriters to upstream's Makefile.
  prePatch = ''
    ${python3}/bin/python3 - <<'PYTHON'
    from pathlib import Path
    for path in Path("upstream_repo/AltServer").glob("*"):
        if path.suffix in (".cpp", ".hpp", ".h"):
            path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n"))
    PYTHON
  '';
  patches = [ ./altserver/reliability.patch ];
  dontStrip = true;
  dontConfigure = true;
  nativeBuildInputs = [
    makeWrapper
    proot
  ];
  doCheck = true;

  buildPhase = ''
    runHook preBuild
    cp ${../tests/altserver/regression.cpp} regression.cpp
    cp ${../tests/altserver/device.cpp} device.cpp
    cp ${../tests/altserver/regression.mak} regression.mak
    mkdir build
    # PRoot uses the pinned userspace toolchain inside Nix's normal sandbox.
    # Bind only the build directory and standard virtual filesystems.
    proot -r ${builderRoot} -b "$PWD:/workdir" -b "$TMPDIR:/tmp" \
      -b /dev -b /proc -w /workdir/build \
      /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp \
      /bin/bash -ec 'make -f ../makefiles/libimobiledevice-build/libimobiledevice.mak -j8; make -f ../regression.mak -j8 all regression device-regression'
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    timeout 60 build/regression
    ${python3}/bin/python3 ${../tests/altserver/fixtures.py} fixtures
    timeout 30 build/device-regression "$PWD/fixtures"
    ${python3}/bin/python3 ${../tests/altserver/daemon.py} build/AltServer-x86_64
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 build/AltServer-x86_64 "$out/libexec/AltServer"
    mkdir -p "$out/etc/ssl"
    ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt "$out/etc/ssl/cert.pem"
    ln -s ${cacert}/etc/ssl/certs "$out/etc/ssl/certs"

    # The static LibreSSL build ignores SSL_CERT_FILE and opens this FHS path.
    # Supply it only inside the process's mount namespace. The root bind is
    # nodev; explicitly restore the one device LibreSSL needs for randomness.
    makeWrapper ${bubblewrap}/bin/bwrap "$out/bin/alt-server" \
      --add-flags "--die-with-parent --bind / / --dev-bind /dev/urandom /dev/urandom --ro-bind $out/etc/ssl /etc/ssl -- $out/libexec/AltServer" \
      --prefix PATH : ${lib.makeBinPath [ python3 ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ avahi-compat ]} \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set-default PYTHONUNBUFFERED 1

    runHook postInstall
  '';

  meta = {
    description = "AltServer Linux NG with current iOS signing and anisette v3 support";
    homepage = "https://github.com/jaakkopalvaila/AltServer-Linux";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "alt-server";
  };
}
