{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  sassc,
}:
let
  rev = "36d24ba0fed2b5274cfe28100a3104465fb69516";
in
stdenvNoCC.mkDerivation {
  pname = "darkly-gtk";
  version = "unstable-${builtins.substring 0 8 rev}";

  src = fetchFromGitHub {
    owner = "wrymt";
    repo = "darkly-gtk";
    inherit rev;
    hash = "sha256-9qJ/nKXNXbX9e7iUt906gxordEU4VMXhq5Vhs9uQ7b8=";
  };

  nativeBuildInputs = [ sassc ];

  installPhase = ''
    runHook preInstall

    # Upstream expects this file to exist; keep default settings.
    : > sass/_darkly_user_settings.scss

    mkdir -p build
    sassc -M -t compact sass/gtk3-light.scss build/gtk3-light.css
    sassc -M -t compact sass/gtk3-dark.scss build/gtk3-dark.css
    sassc -M -t compact sass/gtk4.scss build/gtk4.css

    theme_root="$out/share/themes/Darkly"
    mkdir -p "$theme_root"/assets "$theme_root"/gtk-3.0 "$theme_root"/gtk-4.0

    cp assets/*.png "$theme_root"/assets/
    cp assets/*.svg "$theme_root"/assets/

    ln -sfn ../assets "$theme_root"/gtk-3.0/darkly-gtk-assets
    ln -sfn ../assets "$theme_root"/gtk-4.0/darkly-gtk-assets
    ln -sfn ./gtk.css "$theme_root"/gtk-4.0/gtk-dark.css

    cp build/gtk3-light.css "$theme_root"/gtk-3.0/gtk.css
    cp build/gtk3-dark.css "$theme_root"/gtk-3.0/gtk-dark.css
    cp build/gtk4.css "$theme_root"/gtk-4.0/gtk.css

    runHook postInstall
  '';

  meta = {
    description = "Darkly GTK theme";
    homepage = "https://github.com/wrymt/darkly-gtk";
    license = lib.licenses.lgpl21Only;
    platforms = lib.platforms.linux;
  };
}
