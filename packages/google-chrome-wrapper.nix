{
  fetchurl,
  google-chrome,
  makeWrapper,
  symlinkJoin,
}:
let
  chromeAngleFlags = "--use-gl=angle --use-angle=vulkan --enable-features=Vulkan,VulkanFromANGLE";
  googleChrome = google-chrome.overrideAttrs (
    finalAttrs: _previousAttrs: {
      version = "151.0.7922.173";
      src = fetchurl {
        url = "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${finalAttrs.version}-1_amd64.deb";
        hash = "sha256-h45atJW4ppSYD8phvAmzfmUcztziKRxzQ00W5IomRv0=";
      };

      # Chrome 151 no longer ships lib*GL* files; nixos-25.11 still tries to
      # patch them, while current nixpkgs has removed this obsolete command.
      installPhase =
        builtins.replaceStrings [ "patchelf --set-rpath $rpath $out/share/google/$appname/lib*GL*" ] [ ":" ]
          _previousAttrs.installPhase;
    }
  );
in
symlinkJoin {
  name = "ted-google-chrome";
  paths = [ googleChrome ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    rm -f "$out/bin/google-chrome-stable"
    makeWrapper ${googleChrome}/bin/google-chrome-stable "$out/bin/google-chrome-stable" \
      --add-flags "${chromeAngleFlags}"

    for desktop in "$out/share/applications/google-chrome.desktop" "$out/share/applications/com.google.Chrome.desktop"; do
      if [ -e "$desktop" ]; then
        base_name="''${desktop##*/}"
        rm -f "$desktop"
        cp "${googleChrome}/share/applications/$base_name" "$desktop"
        substituteInPlace "$desktop" \
          --replace "${googleChrome}/bin/google-chrome-stable %U" "$out/bin/google-chrome-stable %U" \
          --replace "${googleChrome}/bin/google-chrome-stable" "$out/bin/google-chrome-stable"
      fi
    done
  '';

  meta = googleChrome.meta // {
    mainProgram = "google-chrome-stable";
  };
}
