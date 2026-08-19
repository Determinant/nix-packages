{
  lib,
  coreutils,
  makeWrapper,
  morgen,
  perl,
  runtimeShell,
  symlinkJoin,
}:
symlinkJoin {
  name = "ted-morgen";
  paths = [ morgen ];
  nativeBuildInputs = [
    makeWrapper
    perl
  ];

  postBuild = ''
    rm -f "$out/bin/morgen"
    makeWrapper ${morgen}/bin/morgen "$out/bin/morgen" \
      --unset NIXOS_OZONE_WL \
      --add-flags "--ozone-platform=x11" \
      --add-flags "--class=morgen"

    # Keep the app-managed per-user autostart entry disabled so only the
    # managed NixOS autostart entry is used.
    cat > "$out/bin/morgen-launch" <<EOF_MORGEN_LAUNCH
    #!${runtimeShell}
    set -e

    autostart_dir="\$HOME/.config/autostart"
    if [ -n "\$XDG_CONFIG_HOME" ]; then
      autostart_dir="\$XDG_CONFIG_HOME/autostart"
    fi
    autostart_file="\$autostart_dir/morgen.desktop"

    disable_app_managed_autostart() {
      ${lib.getExe' coreutils "mkdir"} -p "\$autostart_dir"
      cat > "\$autostart_file" <<'AUTOSTART_EOF'
    [Desktop Entry]
    Type=Application
    Hidden=true
    AUTOSTART_EOF
    }

    disable_app_managed_autostart

    "$out/bin/morgen" "\$@"
    status=\$?

    # Morgen can rewrite ~/.config/autostart/morgen.desktop during runtime.
    # Rewrite it once more on exit so the next login does not regenerate the
    # crashing app-morgen@autostart unit.
    disable_app_managed_autostart

    exit "\$status"
    EOF_MORGEN_LAUNCH
    chmod 0755 "$out/bin/morgen-launch"

    desktop="$out/share/applications/morgen.desktop"
    if [ -e "$desktop" ]; then
      rm -f "$desktop"
      cp "${morgen}/share/applications/morgen.desktop" "$desktop"
      substituteInPlace "$desktop" \
        --replace "${morgen}/bin/morgen %U" "$out/bin/morgen-launch %U" \
        --replace "${morgen}/bin/morgen" "$out/bin/morgen-launch"
      if grep -q '^StartupWMClass=' "$desktop"; then
        perl -i -pe 's/^StartupWMClass=.*/StartupWMClass=morgen/' "$desktop"
      else
        printf '\nStartupWMClass=morgen\n' >> "$desktop"
      fi
    fi

    # Use a dedicated filename so a stale ~/.config/autostart/morgen.desktop
    # cannot suppress startup of the managed entry.
    autostart="$out/etc/xdg/autostart/morgen-nixos.desktop"
    mkdir -p "$(dirname "$autostart")"
    cat > "$autostart" <<EOF_MORGEN_AUTOSTART
    [Desktop Entry]
    Type=Application
    Version=1.0
    Name=Morgen
    Comment=Morgen Startup Script
    Exec=$out/bin/morgen-launch --hidden
    TryExec=$out/bin/morgen-launch
    StartupNotify=false
    Terminal=false
    OnlyShowIn=KDE;
    EOF_MORGEN_AUTOSTART

    # Override the generated app-morgen@autostart service name so a stale
    # ~/.config/autostart/morgen.desktop cannot run a broken raw electron
    # command. The managed morgen-nixos autostart remains the only launcher.
    unit="$out/share/systemd/user/app-morgen@autostart.service"
    mkdir -p "$(dirname "$unit")"
    cat > "$unit" <<EOF_MORGEN_UNIT
    [Unit]
    Description=Ignore upstream Morgen autostart entry
    Documentation=man:systemd-xdg-autostart-generator(8)

    [Service]
    Type=oneshot
    ExecStart=${lib.getExe' coreutils "true"}
    EOF_MORGEN_UNIT
  '';

  meta = morgen.meta // {
    mainProgram = "morgen";
  };
}
