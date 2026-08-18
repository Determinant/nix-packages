{
  lib,
  stdenv,
  fetchurl,
  withAi ? false,

  # nativeBuildInputs
  cmake,
  desktop-file-utils,
  intltool,
  llvmPackages,
  ninja,
  perl,
  pkg-config,
  wrapGAppsHook3,
  saxon,

  # buildInputs
  SDL2,
  adwaita-icon-theme,
  alsa-lib,
  cairo,
  curl,
  exiv2,
  glib,
  glib-networking,
  gmic,
  graphicsmagick,
  gtk3,
  icu,
  isocodes,
  jasper,
  json-glib,
  lcms2,
  lensfun,
  lerc,
  libaom,
  libarchive,
  libavif,
  libdatrie,
  libepoxy,
  libexif,
  libgcrypt,
  libgpg-error,
  libgphoto2,
  libheif,
  libjpeg,
  libjxl,
  libpng,
  librsvg,
  libsecret,
  libsysprof-capture,
  libthai,
  libtiff,
  libwebp,
  libxml2,
  lua5_4,
  onnxruntime,
  util-linux,
  openexr,
  openjpeg,
  osm-gps-map,
  pcre2,
  portmidi,
  potrace,
  pugixml,
  sqlite,

  # Linux only
  colord,
  colord-gtk,
  libselinux,
  libsepol,
  libx11,
  libxdmcp,
  libxkbcommon,
  libxtst,
  ocl-icd,

  # Darwin only
  gtk-mac-integration,

  versionCheckHook,
  gitUpdater,
}:
let
  pugixml-shared = pugixml.override { shared = true; };
in
stdenv.mkDerivation rec {
  pname = "darktable";
  version = "5.6.0";

  src = fetchurl {
    url = "https://github.com/darktable-org/darktable/releases/download/release-${version}/darktable-${version}.tar.xz";
    hash = "sha256-FX1tOEevivyr54lERUeG9zqIbgilBLS9YRTCBl/gBuQ=";
  };

  nativeBuildInputs = [
    cmake
    desktop-file-utils
    intltool
    llvmPackages.llvm
    ninja
    perl
    pkg-config
    wrapGAppsHook3
    saxon
  ];

  buildInputs = [
    SDL2
    adwaita-icon-theme
    cairo
    curl
    exiv2
    glib
    glib-networking
    gmic
    graphicsmagick
    gtk3
    icu
    isocodes
    jasper
    json-glib
    lcms2
    lensfun
    lerc
    libaom
    libavif
    libdatrie
    libepoxy
    libexif
    libgcrypt
    libgpg-error
    libgphoto2
    libheif
    libjpeg
    libjxl
    libpng
    librsvg
    libsecret
    libsysprof-capture
    libthai
    libtiff
    libwebp
    libxml2
    lua5_4
    openexr
    openjpeg
    osm-gps-map
    pcre2
    portmidi
    potrace
    pugixml-shared
    sqlite
  ]
  ++ lib.optionals withAi [
    libarchive
    onnxruntime
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    colord
    colord-gtk
    libselinux
    libsepol
    libx11
    libxdmcp
    libxkbcommon
    libxtst
    ocl-icd
    util-linux
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin gtk-mac-integration
  ++ lib.optional stdenv.cc.isClang llvmPackages.openmp;

  cmakeFlags = [
    "-DBUILD_USERMANUAL=False"
  ]
  ++ lib.optionals withAi [
    (lib.cmakeBool "USE_AI" true)
    (lib.cmakeBool "ONNXRUNTIME_OFFLINE" true)
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "-DUSE_COLORD=OFF"
    "-DUSE_KWALLET=OFF"
  ];

  # darktable's binaries load libraries and OpenCL kernels from package-specific
  # directories, so make those paths explicit in the generated wrappers.
  preFixup =
    let
      libPathEnvVar = if stdenv.hostPlatform.isDarwin then "DYLD_LIBRARY_PATH" else "LD_LIBRARY_PATH";
      libPathPrefix =
        "$out/lib/darktable"
        + lib.optionalString (withAi && stdenv.hostPlatform.isLinux) ":${lib.getLib onnxruntime}/lib"
        + lib.optionalString stdenv.hostPlatform.isLinux ":${ocl-icd}/lib";
    in
    ''
      for kernel in $out/share/darktable/kernels/*.cl; do
        sed -r "s|#include \"(.*)\"|#include \"$out/share/darktable/kernels/\1\"|g" -i "$kernel"
      done

      gappsWrapperArgs+=(
        --prefix ${libPathEnvVar} ":" "${libPathPrefix}"
      )
    '';

  postPatch = ''
    patchShebangs ./tools/generate_styles_string.sh
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru.updateScript = gitUpdater {
    rev-prefix = "release-";
    odd-unstable = true;
    url = "https://github.com/darktable-org/darktable.git";
  };

  meta = {
    description = "Virtual lighttable and darkroom for photographers";
    homepage = "https://www.darktable.org";
    changelog = "https://github.com/darktable-org/darktable/releases/tag/release-${version}";
    mainProgram = "darktable";
    license = lib.licenses.gpl3Plus;
    platforms = with lib.platforms; linux ++ darwin;
  };
}
