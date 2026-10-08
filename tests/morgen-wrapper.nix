{ pkgs }:
let
  mockMorgen = pkgs.runCommand "mock-morgen" { } ''
    mkdir -p "$out/bin" "$out/share/applications"
    cat > "$out/bin/morgen" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    printf '%s\n' "$@" > "$TEST_OUTPUT/args"
    printf '%s\n' "''${GTK_MODULES-}" > "$TEST_OUTPUT/gtk-modules"
    test -z "''${NIXOS_OZONE_WL-}"
    autostart="''${XDG_CONFIG_HOME:-$HOME/.config}/autostart/morgen.desktop"
    grep -qx 'Hidden=true' "$autostart"
    printf '%s\n' '[Desktop Entry]' 'Exec=stale-electron --hidden' > "$autostart"
    exit "$TEST_EXIT_CODE"
    EOF
    chmod +x "$out/bin/morgen"
    cat > "$out/share/applications/morgen.desktop" <<EOF
    [Desktop Entry]
    Type=Application
    Name=Morgen
    Exec=$out/bin/morgen %U
    EOF
  '';
  mkWrapper =
    gtkModules:
    pkgs.callPackage ../packages/morgen-wrapper.nix {
      morgen = mockMorgen;
      inherit gtkModules;
    };
  defaultWrapper = mkWrapper [ ];
  kdeWrapper = mkWrapper [
    "colorreload-gtk-module"
    "window-decorations-gtk-module"
  ];
in
pkgs.runCommand "morgen-wrapper-tests" { } ''
  export HOME="$TMPDIR/home"
  export TEST_OUTPUT="$TMPDIR/output"
  export NIXOS_OZONE_WL=1
  export GTK_MODULES=existing-module
  mkdir -p "$HOME" "$TEST_OUTPUT"

  for wrapper in ${defaultWrapper} ${kdeWrapper}; do
    for config_mode in default custom; do
      if [ "$config_mode" = custom ]; then
        export XDG_CONFIG_HOME="$TMPDIR/custom-config"
      else
        unset XDG_CONFIG_HOME
      fi
      autostart="''${XDG_CONFIG_HOME:-$HOME/.config}/autostart/morgen.desktop"
      for TEST_EXIT_CODE in 0 139; do
        export TEST_EXIT_CODE
        status=0
        "$wrapper/bin/morgen-launch" --hidden 'argument with spaces' || status=$?
        test "$status" = "$TEST_EXIT_CODE"
        grep -qx 'Hidden=true' "$autostart"
        if grep -q 'stale-electron' "$autostart"; then
          echo "Launcher left a stale autostart command" >&2
          exit 1
        fi
        printf '%s\n' --ozone-platform=x11 --class=morgen --hidden 'argument with spaces' > expected-args
        diff -u expected-args "$TEST_OUTPUT/args"
        if [ "$wrapper" = ${kdeWrapper} ]; then
          grep -qx 'colorreload-gtk-module:window-decorations-gtk-module:existing-module' "$TEST_OUTPUT/gtk-modules"
        else
          grep -qx 'existing-module' "$TEST_OUTPUT/gtk-modules"
        fi
      done
    done
    grep -Fx "Exec=$wrapper/bin/morgen-launch %U" "$wrapper/share/applications/morgen.desktop"
    grep -Fx "Exec=$wrapper/bin/morgen-launch --hidden" "$wrapper/etc/xdg/autostart/morgen-nixos.desktop"
  done
  touch "$out"
''
