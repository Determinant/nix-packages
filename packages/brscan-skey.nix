{
  lib,
  stdenvNoCC,
  fetchurl,
  binutils,
  xz,
  runtimeShell,
  sane-backends,
  avahi-compat,
  brscan4,
  brscan5,
}:
stdenvNoCC.mkDerivation rec {
  pname = "brscan-skey";
  version = "0.3.4-0";

  src = fetchurl {
    url = "https://download.brother.com/pub/com/linux/linux/packages/${pname}-${version}.amd64.deb";
    hash = "sha256-Y2D35vu1XdqdzQWgMNyhLlb42M4Dd9SoNilwhPXOqJE=";
  };

  nativeBuildInputs = [
    binutils
    xz
  ];

  unpackPhase = ''
    ar x "$src"
    tar xf data.tar.xz
  '';

  installPhase = ''
    runHook preInstall

    install -d "$out/opt/brother/scanner"
    cp -rp opt/brother/scanner/brscan-skey "$out/opt/brother/scanner/"

    install -d "$out/bin"
    ln -s "$out/opt/brother/scanner/brscan-skey/skey-scanimage" "$out/bin/skey-scanimage"

    cat > "$out/bin/brscan-skey" <<EOF
    #!${runtimeShell}
    set -eu
    runtime_lib_path="${
      lib.makeLibraryPath [
        sane-backends
        avahi-compat
      ]
    }:${brscan4}/lib/sane:${brscan5}/lib/sane"
    if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
      export LD_LIBRARY_PATH="\$runtime_lib_path:\$LD_LIBRARY_PATH"
    else
      export LD_LIBRARY_PATH="\$runtime_lib_path"
    fi
    exec "$out/opt/brother/scanner/brscan-skey/brscan-skey" "\$@"
    EOF
    chmod 0755 "$out/bin/brscan-skey"

    runHook postInstall
  '';

  meta = {
    description = "Brother Scan Key Tool for push scanning from MFP panel";
    homepage = "https://support.brother.com/";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "brscan-skey";
  };
}
