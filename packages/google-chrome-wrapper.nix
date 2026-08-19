{
  google-chrome,
  makeWrapper,
  symlinkJoin,
}:
let
  chromeAngleFlags = "--use-gl=angle --use-angle=vulkan --enable-features=Vulkan,VulkanFromANGLE";
in
symlinkJoin {
  name = "ted-google-chrome";
  paths = [ google-chrome ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    rm -f "$out/bin/google-chrome-stable"
    makeWrapper ${google-chrome}/bin/google-chrome-stable "$out/bin/google-chrome-stable" \
      --add-flags "${chromeAngleFlags}"

    for desktop in "$out/share/applications/google-chrome.desktop" "$out/share/applications/com.google.Chrome.desktop"; do
      if [ -e "$desktop" ]; then
        base_name="''${desktop##*/}"
        rm -f "$desktop"
        cp "${google-chrome}/share/applications/$base_name" "$desktop"
        substituteInPlace "$desktop" \
          --replace "${google-chrome}/bin/google-chrome-stable %U" "$out/bin/google-chrome-stable %U" \
          --replace "${google-chrome}/bin/google-chrome-stable" "$out/bin/google-chrome-stable"
      fi
    done
  '';

  meta = google-chrome.meta // {
    mainProgram = "google-chrome-stable";
  };
}
