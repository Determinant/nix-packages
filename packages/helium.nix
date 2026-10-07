{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  desktop-file-utils,
  versionCheckHook,
  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libGL,
  libpulseaudio,
  libva,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  pipewire,
  qt6,
  systemdLibs,
  vulkan-loader,
  xdg-utils,
  commandLineArgs ? [ ],
}:
let
  release = lib.importJSON ./helium-sources.json;
in
stdenv.mkDerivation {
  pname = "helium";
  inherit (release) version;

  src = fetchurl release.sources.${stdenv.hostPlatform.system};

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];
  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    qt6.qtbase
    systemdLibs
  ];

  dontWrapQtApps = true;
  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt/helium" "$out/bin"
    cp -a ./. "$out/opt/helium/"
    # Only ship the supported Qt 6 shim; keep dependency checking strict.
    rm -f "$out/opt/helium/libqt5_shim.so"
    # Use Nix's Vulkan loader with the host's graphics drivers, like Chromium.
    rm "$out/opt/helium/libvulkan.so.1"
    ln -s "${lib.getLib vulkan-loader}/lib/libvulkan.so.1" "$out/opt/helium/libvulkan.so.1"
    install -Dm644 helium.desktop "$out/share/applications/helium.desktop"
    substituteInPlace "$out/share/applications/helium.desktop" \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
    install -Dm644 product_logo_256.png \
      "$out/share/icons/hicolor/256x256/apps/helium.png"

    runHook postInstall
  '';

  preFixup = ''
    # Invoke the binary directly: the upstream wrapper overwrites CHROME_WRAPPER
    # with a versioned store path. A stable name keeps PWA launchers usable after
    # profile upgrades and garbage collection, as in Nixpkgs' Chromium package.
    makeWrapper "$out/opt/helium/helium" "$out/bin/helium" \
      "''${gappsWrapperArgs[@]}" \
      --prefix LD_LIBRARY_PATH : "$out/opt/helium:$out/opt/helium/lib:$out/opt/helium/lib.target:${
        lib.makeLibraryPath [
          libGL
          libva
          pipewire
          libpulseaudio
        ]
      }" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --set CHROME_WRAPPER helium \
      --set CHROME_DESKTOP helium.desktop \
      --set CHROME_VERSION_EXTRA nix \
      --add-flags ${lib.escapeShellArg (lib.escapeShellArgs commandLineArgs)}
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    desktop-file-utils
  ];
  doInstallCheck = true;
  postInstallCheck = ''
    desktop-file-validate "$out/share/applications/helium.desktop"
  '';

  meta = {
    description = "Private web browser based on Chromium";
    homepage = "https://helium.computer/";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${release.version}";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "helium";
  };
}
