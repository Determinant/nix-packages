{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ted.brscanSkey;
  brscanSkeyDaemon = pkgs.writeShellScript "ted-brscan-skey-daemon" ''
    set -eu

    cfg_dir="$HOME/.brscan-skey"
    ${pkgs.coreutils}/bin/mkdir -p "$cfg_dir"

    pkg_skey="${pkgs.brscan-skey}/opt/brother/scanner/brscan-skey"

    for cfg in scantoemail.config scantofile.config scantoimage.config scantoocr.config; do
      if [ ! -e "$cfg_dir/$cfg" ]; then
        ${pkgs.coreutils}/bin/cp "$pkg_skey/$cfg" "$cfg_dir/$cfg"
      fi
      ${pkgs.coreutils}/bin/chmod u+w "$cfg_dir/$cfg" >/dev/null 2>&1 || true
      ${pkgs.gnused}/bin/sed -i 's/^resolution=.*/resolution=300/' "$cfg_dir/$cfg"
    done

    runtime_root="$HOME/.local/state/brscan-skey"
    runtime_opt_skey="$runtime_root/opt/brother/scanner/brscan-skey"
    runtime_etc_scanner="$runtime_root/etc/opt/brother/scanner"
    runtime_etc_brscan4="$runtime_etc_scanner/brscan4"
    runtime_etc_skey="$runtime_etc_scanner/brscan-skey"
    runtime_brscan4_cfg="$runtime_etc_brscan4/brsanenetdevice4.cfg"
    runtime_skey_cfg="$runtime_opt_skey/brscan-skey.config"

    ${pkgs.coreutils}/bin/mkdir -p "$runtime_opt_skey" "$runtime_etc_brscan4" "$runtime_etc_skey"
    if [ ! -e "$runtime_opt_skey/brscan-skey-exe" ]; then
      ${pkgs.coreutils}/bin/cp -r "$pkg_skey/." "$runtime_opt_skey/"
    fi
    if [ ! -e "$runtime_etc_brscan4/models4" ]; then
      ${pkgs.coreutils}/bin/cp -r "${pkgs.brscan4}/opt/brother/scanner/brscan4/models4" "$runtime_etc_brscan4/"
    fi
    if [ ! -e "$runtime_etc_brscan4/Brsane4.ini" ]; then
      ${pkgs.coreutils}/bin/cp "${pkgs.brscan4}/opt/brother/scanner/brscan4/Brsane4.ini" "$runtime_etc_brscan4/Brsane4.ini"
    fi
    if [ ! -e "$runtime_brscan4_cfg" ]; then
      system_brscan4_cfg="/etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg"
      if [ -r "$system_brscan4_cfg" ] && ${pkgs.gnugrep}/bin/grep -q '^DEVICE=' "$system_brscan4_cfg"; then
        ${pkgs.coreutils}/bin/cp "$system_brscan4_cfg" "$runtime_brscan4_cfg"
      else
        ${pkgs.coreutils}/bin/cp "${pkgs.brscan4}/opt/brother/scanner/brscan4/brsanenetdevice4.cfg" "$runtime_brscan4_cfg"
      fi
    fi
    if [ ! -e "$runtime_etc_skey/brscan-snmp.cfg" ]; then
      ${pkgs.coreutils}/bin/cp "$runtime_opt_skey/brscan-snmp.cfg" "$runtime_etc_skey/brscan-snmp.cfg"
    fi

    ${pkgs.coreutils}/bin/chmod -R u+rwX "$runtime_opt_skey" "$runtime_etc_brscan4" "$runtime_etc_skey" >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/chmod u+w "$runtime_skey_cfg" "$runtime_opt_skey/brscan-snmp.cfg" "$runtime_brscan4_cfg" "$runtime_etc_skey/brscan-snmp.cfg" >/dev/null 2>&1 || true

    if [ ! -e "$runtime_opt_skey/skey-scanimage-bin" ] && [ -e "$runtime_opt_skey/skey-scanimage" ]; then
      ${pkgs.coreutils}/bin/mv "$runtime_opt_skey/skey-scanimage" "$runtime_opt_skey/skey-scanimage-bin"
    fi

    cat > "$runtime_opt_skey/skey-scanimage" <<'EOF_SKEY_SCANIMAGE_WRAPPER'
    #!${pkgs.runtimeShell}
    set -eu

    runtime_lib_path="${
      lib.makeLibraryPath [
        pkgs.sane-backends
        pkgs."avahi-compat"
      ]
    }:${pkgs.brscan4}/lib/sane:${pkgs.brscan5}/lib/sane"
    if [ -n "''${LD_LIBRARY_PATH:-}" ]; then
      export LD_LIBRARY_PATH="$runtime_lib_path:$LD_LIBRARY_PATH"
    else
      export LD_LIBRARY_PATH="$runtime_lib_path"
    fi

    output_file=""
    resolution="300"
    expect=""

    for arg in "$@"; do
      if [ "$expect" = "output_file" ]; then
        output_file="$arg"
        expect=""
        continue
      fi
      if [ "$expect" = "resolution" ]; then
        resolution="$arg"
        expect=""
        continue
      fi
      case "$arg" in
        --outputfile|--output-file)
          expect="output_file"
          ;;
        --resolution)
          expect="resolution"
          ;;
      esac
    done

    /opt/brother/scanner/brscan-skey/skey-scanimage-bin "$@" || true
    if [ -n "$output_file" ] && [ -s "$output_file" ]; then
      exit 0
    fi

    escl_device="$(${pkgs.sane-backends}/bin/scanimage -L 2>/dev/null | ${pkgs.gnugrep}/bin/grep -m1 -Eo 'escl:http://[0-9.]+(:[0-9]+)?' || true)"
    if [ -z "$escl_device" ] && [ -r /etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg ]; then
      scanner_ip="$(${pkgs.gnugrep}/bin/grep -m1 -Eo 'IP-ADDRESS=[0-9.]+' /etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg | ${pkgs.gnused}/bin/sed 's/^IP-ADDRESS=//' || true)"
      if [ -n "$scanner_ip" ]; then
        escl_device="escl:http://$scanner_ip:80"
      fi
    fi

    if [ -n "$escl_device" ] && [ -n "$output_file" ]; then
      ${pkgs.sane-backends}/bin/scanimage -d "$escl_device" --resolution "$resolution" --format=tiff > "$output_file" || true
    fi
    exit 0
    EOF_SKEY_SCANIMAGE_WRAPPER
    ${pkgs.coreutils}/bin/chmod 0755 "$runtime_opt_skey/skey-scanimage"

    tmp_skey_cfg="$(${pkgs.coreutils}/bin/mktemp)"
    ${pkgs.gnugrep}/bin/grep -Ev '^(IMAGE|OCR|EMAIL|FILE)=' "$runtime_skey_cfg" > "$tmp_skey_cfg" || true
    cat >> "$tmp_skey_cfg" <<EOF_RUNTIME_SKEY_CONFIG
    IMAGE="${pkgs.runtimeShell}  /opt/brother/scanner/brscan-skey/script/scantofile.sh"
    OCR="${pkgs.runtimeShell}  /opt/brother/scanner/brscan-skey/script/scantoocr.sh"
    EMAIL="${pkgs.runtimeShell}  /opt/brother/scanner/brscan-skey/script/scantoemail.sh"
    FILE="${pkgs.runtimeShell}  /opt/brother/scanner/brscan-skey/script/scantofile.sh"
    EOF_RUNTIME_SKEY_CONFIG
    ${pkgs.coreutils}/bin/cp "$tmp_skey_cfg" "$runtime_skey_cfg"
    ${pkgs.coreutils}/bin/rm -f "$tmp_skey_cfg"

    run_skey() {
      ${pkgs.bubblewrap}/bin/bwrap \
        --bind / / \
        --dev-bind /dev /dev \
        --proc /proc \
        --bind "$runtime_opt_skey" /opt/brother/scanner/brscan-skey \
        --bind "$runtime_etc_scanner" /etc/opt/brother/scanner \
        ${pkgs.brscan-skey}/bin/brscan-skey "$@"
    }

    scanner_ip=""
    scanner_model=""
    detect_attempt=0

    while [ "$detect_attempt" -lt 10 ] && { [ -z "$scanner_ip" ] || [ -z "$scanner_model" ]; }; do
      mdns_line="$(${pkgs.avahi}/bin/avahi-browse -rtp _scanner._tcp 2>/dev/null | ${pkgs.gawk}/bin/awk -F';' '$1 == "=" && $3 == "IPv4" && $4 ~ /^Brother/ { print; exit }' || true)"
      if [ -n "$mdns_line" ]; then
        scanner_ip="$(printf '%s\n' "$mdns_line" | ${pkgs.gawk}/bin/awk -F';' '{ print $8 }')"
        scanner_txt="$(printf '%s\n' "$mdns_line" | ${pkgs.gawk}/bin/awk -F';' '{ if (NF >= 10) print $10 }')"
        scanner_model="$(printf '%s\n' "$scanner_txt" | ${pkgs.gnused}/bin/sed -n 's/.*"mdl=\([^\"]*\)".*/\1/p' | ${pkgs.gnused}/bin/sed 's/ [sS]eries$//' | ${pkgs.gawk}/bin/awk '{ print $1 }')"
      fi

      if [ -z "$scanner_ip" ] || [ -z "$scanner_model" ]; then
        scan_line="$(${pkgs.coreutils}/bin/timeout 4s ${pkgs.sane-backends}/bin/scanimage -L 2>/dev/null | ${pkgs.gnugrep}/bin/grep -m1 -E 'escl:http://[0-9.]+' || true)"
        if [ -n "$scan_line" ]; then
          if [ -z "$scanner_ip" ]; then
            scanner_ip="$(printf '%s\n' "$scan_line" | ${pkgs.gnused}/bin/sed -n 's|.*escl:http://\([0-9.]*\):.*|\1|p')"
          fi
          if [ -z "$scanner_model" ]; then
            scanner_model="$(printf '%s\n' "$scan_line" | ${pkgs.gnused}/bin/sed -n 's/.*Brother \([^[]*\)\[[0-9.]*\].*/\1/p' | ${pkgs.gnused}/bin/sed 's/ [sS]eries$//' | ${pkgs.gawk}/bin/awk '{ print $1 }')"
          fi
        fi
      fi

      detect_attempt=$((detect_attempt + 1))
      if { [ -z "$scanner_ip" ] || [ -z "$scanner_model" ]; } && [ "$detect_attempt" -lt 10 ]; then
        ${pkgs.coreutils}/bin/sleep 2
      fi
    done

    if [ -n "$scanner_ip" ] && [ -n "$scanner_model" ]; then
      scanner_name="$(printf '%s' "$scanner_model" | ${pkgs.gnused}/bin/sed 's/[^[:alnum:]_-]//g')"
      if [ -z "$scanner_name" ]; then
        scanner_name="scanner"
      fi
      tmp_cfg="$(${pkgs.coreutils}/bin/mktemp)"
      BRSANENETDEVICE4_CFG_FILENAME="$tmp_cfg" ${pkgs.brscan4}/bin/brsaneconfig4 -a name="$scanner_name" model="$scanner_model" ip="$scanner_ip" >/dev/null 2>&1 || true
      if [ -s "$tmp_cfg" ]; then
        ${pkgs.coreutils}/bin/cp "$tmp_cfg" "$runtime_brscan4_cfg"
      fi
      ${pkgs.coreutils}/bin/rm -f "$tmp_cfg"
    fi

    if ! ${pkgs.gnugrep}/bin/grep -q '^DEVICE=' "$runtime_brscan4_cfg"; then
      echo "brscan-skey: scanner not discovered yet; waiting for next restart" >&2
      exit 1
    fi

    raw_name="$(${pkgs.coreutils}/bin/cat /proc/sys/kernel/hostname)"
    user_name="$(printf '%s' "$raw_name" | ${pkgs.gnused}/bin/sed 's/[^[:alnum:]]//g' | ${pkgs.coreutils}/bin/cut -c1-15)"
    if [ -z "$user_name" ]; then
      user_name="LinuxPC"
    fi

    if [ -z "$scanner_ip" ] && [ -r "$runtime_brscan4_cfg" ]; then
      scanner_ip="$(${pkgs.gnugrep}/bin/grep -m1 -Eo 'IP-ADDRESS=[0-9.]+' "$runtime_brscan4_cfg" | ${pkgs.gnused}/bin/sed 's/^IP-ADDRESS=//' || true)"
    fi

    host_ip=""
    if [ -n "$scanner_ip" ]; then
      host_ip="$(${pkgs.iproute2}/bin/ip -4 route get "$scanner_ip" | ${pkgs.gawk}/bin/awk 'NR==1 { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true)"
    fi
    if [ -z "$host_ip" ]; then
      default_if="$(${pkgs.iproute2}/bin/ip -4 route show default | ${pkgs.gawk}/bin/awk 'NR==1 { print $5 }')"
      if [ -n "$default_if" ]; then
        host_ip="$(${pkgs.iproute2}/bin/ip -4 -o addr show dev "$default_if" scope global | ${pkgs.gawk}/bin/awk 'NR==1 { sub(/\/.*/, "", $4); print $4 }')"
      fi
    fi
    if [ -z "$host_ip" ]; then
      host_ip="$(${pkgs.iproute2}/bin/ip -4 -o addr show scope global | ${pkgs.gawk}/bin/awk 'NR==1 { sub(/\/.*/, "", $4); print $4 }')"
    fi

    if [ -n "$host_ip" ]; then
      ${pkgs.gnused}/bin/sed -i '/^ip_address=/d' "$runtime_skey_cfg"
      printf 'ip_address=%s\n' "$host_ip" >> "$runtime_skey_cfg"
    fi

    run_skey -u "$user_name" >/dev/null 2>&1 || true
    run_skey -f
  '';
in
{
  options.ted.brscanSkey.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable Brother scan-to-PC integration (brscan-skey daemon).";
  };

  config = lib.mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      # Scanner registration is refreshed dynamically at runtime by
      # ted-brscan-skey-daemon, so scanner changes do not require rebuilds.
      brscan4.enable = true;
      brscan5.enable = true;
    };

    systemd.user.services.brscan-skey = {
      description = "Brother scan-to-PC key daemon";
      serviceConfig = {
        ExecStart = "${brscanSkeyDaemon}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    # Migrate old read-only symlink layout to tmpfiles-managed /opt copy.
    system.activationScripts.brscanSkeyMigration = lib.stringAfter [ "etc" ] ''
      if [ -L /opt/brother/scanner/brscan-skey ]; then
        ${pkgs.coreutils}/bin/rm -f /opt/brother/scanner/brscan-skey
      fi
    '';

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /opt/brother 0755 root root -"
      "d /opt/brother/scanner 0755 root root -"
      "L+ /opt/brother/scanner/brscan5 - - - - ${pkgs.brscan5}/opt/brother/scanner/brscan5"
      "d /opt/brother/scanner/brscan-skey 0755 root root -"
      "C /opt/brother/scanner/brscan-skey - - - - ${pkgs.brscan-skey}/opt/brother/scanner/brscan-skey"
    ];
  };
}
