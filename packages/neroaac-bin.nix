{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  patchelf,
  pkgsi686Linux,
}:
let
  src = fetchurl {
    # Match AUR's archived upstream source; ftp6.nero.com has been offline for years.
    url = "https://web.archive.org/web/20170610150750/http://ftp6.nero.com/tools/NeroAACCodec-1.5.1.zip";
    hash = "sha256-4Elq2FbigDABpZmFNo0hsi9PvdVVicfzE9YEDO//ZIs=";
  };
  i686RuntimeLibs = [
    pkgsi686Linux.glibc
    pkgsi686Linux.stdenv.cc.cc.lib
  ];
  i686RuntimePath = lib.makeLibraryPath i686RuntimeLibs;
in
stdenvNoCC.mkDerivation {
  pname = "ted-neroaac-bin";
  version = "1.5.1";
  inherit src;

  nativeBuildInputs = [
    unzip
    patchelf
  ];

  dontConfigure = true;
  dontBuild = true;
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 linux/neroAacEnc "$out/bin/neroAacEnc"
    install -Dm755 linux/neroAacDec "$out/bin/neroAacDec"
    install -Dm755 linux/neroAacTag "$out/bin/neroAacTag"

    # Keep old lowercase command names for compatibility.
    ln -s neroAacEnc "$out/bin/neroaacenc"
    ln -s neroAacDec "$out/bin/neroaacdec"
    ln -s neroAacTag "$out/bin/neroaactag"

    for bin in "$out/bin/neroAacEnc" "$out/bin/neroAacDec" "$out/bin/neroAacTag"; do
      patchelf \
        --set-interpreter ${pkgsi686Linux.glibc}/lib/ld-linux.so.2 \
        --set-rpath "${i686RuntimePath}" \
        "$bin"
    done

    install -Dm644 license.txt "$out/share/licenses/ted-neroaac-bin/LICENSE"
    install -Dm644 readme.txt "$out/share/doc/ted-neroaac-bin/readme.txt"
    install -Dm644 changelog.txt "$out/share/doc/ted-neroaac-bin/changelog.txt"

    runHook postInstall
  '';

  meta = {
    description = "Nero AAC encoder/decoder/tagger CLI binaries (archived upstream ZIP)";
    homepage = "https://www.nero.com";
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "neroAacEnc";
    platforms = [ "x86_64-linux" ];
  };
}
