{ pkgs }:
let
  # Reproduce the 0.12 regression even when the flake pins older Nixpkgs.
  bubblewrap =
    if pkgs.lib.versionAtLeast pkgs.bubblewrap.version "0.12" then
      pkgs.bubblewrap
    else
      pkgs.bubblewrap.overrideAttrs {
        version = "0.12.0";
        src = pkgs.fetchFromGitHub {
          owner = "containers";
          repo = "bubblewrap";
          rev = "v0.12.0";
          hash = "sha256-VnhJ5bej3/GTHcU8+AkyR7f3J0KKDuoc94SFxo4grhk=";
        };
      };
  scannerPackage = pkgs.runCommand "brscan-skey-test-fixture" { } ''
    skey="$out/opt/brother/scanner/brscan-skey"
    mkdir -p "$skey" "$out/bin"
    for name in scantoemail scantofile scantoimage scantoocr; do
      echo resolution=100 > "$skey/$name.config"
    done
    echo fixture-original=1 > "$skey/brscan-skey.config"
    touch "$skey/brscan-skey-exe" "$skey/brscan-snmp.cfg" "$skey/skey-scanimage"
    cat > "$out/bin/brscan-skey" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    case "$1" in
      -u) exit 0 ;;
      -f)
        test "$(cat /opt/brother/scanner/host-sentinel)" = untouched
        test -r /etc/opt/brother/scanner/brscan4/Brsane4.ini
        grep -q '^DEVICE=' /etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg
        echo fixture-writable=1 >> /opt/brother/scanner/brscan-skey/brscan-skey.config
        echo '# fixture-writable' >> /etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg
        touch "$HOME/scanner-ready"
        exec ${pkgs.coreutils}/bin/sleep infinity
        ;;
      *) exit 2 ;;
    esac
    EOF
    chmod +x "$out/bin/brscan-skey"
  '';
  discovery = pkgs.writeShellScriptBin "avahi-browse" ''
    printf '%s\n' '=;eth0;IPv4;Brother scanner;_scanner._tcp;local;scanner.local;192.0.2.20;54921;"mdl=HL-L3290CDW series"'
  '';
in
pkgs.testers.runNixOSTest {
  name = "brscan-skey";
  requiredFeatures.kvm = false;
  globalTimeout = 300;

  nodes.machine = {
    imports = [
      # Only discovery and the vendor executable are fixtures. Exercise the
      # production launcher, Bubblewrap, SANE registration and user service.
      (
        {
          pkgs,
          lib,
          config,
          ...
        }:
        import ../modules/brscan-skey.nix {
          inherit lib config;
          pkgs = pkgs // {
            inherit bubblewrap;
            avahi = discovery;
          };
        }
      )
    ];
    ted.brscanSkey.package = scannerPackage;
    users.users.scanner = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    systemd.tmpfiles.rules = [ "d /opt 0711 root root -" ];
    environment.systemPackages = [ pkgs.util-linux ];
    virtualisation.memorySize = 1024;
    virtualisation.cores = 2;
  };

  testScript = ''
    import shlex

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    def user(command):
        return (
            "runuser -u scanner -- env XDG_RUNTIME_DIR=/run/user/1000 "
            "sh -c " + shlex.quote(command)
        )

    with subtest("manual startup works with a root-owned mode-0711 opt"):
        machine.succeed("test $(stat -c %a /opt) = 711")
        machine.succeed("test $(stat -c %u /opt) = 0")
        machine.succeed("printf untouched > /opt/brother/scanner/host-sentinel")
        machine.fail(user("systemctl --user is-active --quiet brscan-skey.service"))
        machine.succeed(user("systemctl --user start brscan-skey.service"))
        machine.wait_for_file("/home/scanner/scanner-ready", timeout=20)
        machine.succeed(user("systemctl --user is-active --quiet brscan-skey.service"))
        machine.succeed(user("test $(systemctl --user show brscan-skey.service -p NRestarts --value) = 0"))

    with subtest("vendor paths map to writable per-user configuration"):
        runtime = "/home/scanner/.local/state/brscan-skey"
        machine.succeed(f"grep -q '^fixture-writable=1$' {runtime}/opt/brother/scanner/brscan-skey/brscan-skey.config")
        machine.succeed(f"grep -q '^# fixture-writable$' {runtime}/etc/opt/brother/scanner/brscan4/brsanenetdevice4.cfg")
        machine.succeed("grep -q '^resolution=300$' /home/scanner/.brscan-skey/scantofile.config")
        machine.succeed("test $(cat /opt/brother/scanner/host-sentinel) = untouched")
        machine.succeed("test $(stat -c %a /opt) = 711")
        machine.succeed("test $(stat -c %u /opt) = 0")

    with subtest("restart reuses writable state and manual stop stays stopped"):
        machine.succeed("rm /home/scanner/scanner-ready")
        machine.succeed(user("systemctl --user restart brscan-skey.service"))
        machine.wait_for_file("/home/scanner/scanner-ready", timeout=20)
        machine.succeed(user("systemctl --user is-active --quiet brscan-skey.service"))
        machine.succeed(user("systemctl --user stop brscan-skey.service"))
        machine.succeed("sleep 3")
        machine.fail(user("systemctl --user is-active --quiet brscan-skey.service"))
  '';
}
