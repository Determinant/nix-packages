{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  bubblewrap,
  cacert,
  python3,
  avahi-compat,
}:
stdenvNoCC.mkDerivation rec {
  pname = "altserver-linux-ng";
  version = "2026-11-05";

  src = fetchurl {
    url = "https://github.com/jaakkopalvaila/AltServer-Linux/releases/download/ng-${version}/AltServer-x86_64";
    hash = "sha256-jTTkXOaIAe+TviXTBO+0JKIyU0G+UjXWUcNtEYFRopo=";
  };

  dontUnpack = true;
  dontStrip = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/libexec/AltServer"
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
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "alt-server";
  };
}
