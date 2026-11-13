# nix-packages

Personal packages and desktop wrappers for NixOS, available as flake packages
and a Nixpkgs overlay.

## Packages

| Flake package | Overlay attribute | Purpose |
| --- | --- | --- |
| `darktable` | `darktable-latest` | darktable without the optional AI subsystem |
| `darktable-ai` | `darktable-latest-ai` | darktable with ONNX Runtime support |
| `helium` | `helium` | Official Helium Linux binaries |
| `darkly`, `darkly-qt5` | Same names | Darkly Qt themes |
| `darkly-gtk` | `darkly-gtk` | Darkly GTK theme |
| `brscan-skey` | `brscan-skey` | Brother scan-to-PC button support |
| `altserver` | `altserver` | AltServer Linux NG, including the NixOS TLS certificate layout |
| `discord` | `discord` | Discord with the KDE Wayland scaling fix |
| `ted-google-chrome` | `ted-google-chrome` | Pinned Chrome build with Vulkan/ANGLE flags |
| `ted-morgen` | `ted-morgen` | Morgen X11 launcher and KDE autostart |
| `ted-neroaac-bin` | `ted-neroaac-bin` | Archived Nero AAC encoder, decoder, and tagger |
| `ted-ortho4xp-deps` | `ted-ortho4xp-deps` | Python and native dependencies for a separate Ortho4XP checkout |

The default package is `darktable`. The flake targets `x86_64-linux` and
`aarch64-linux`, except for `brscan-skey`, `discord`, `ted-google-chrome`,
`ted-morgen`, and `ted-neroaac-bin`, which are x86_64-only and contain unfree
software. Standalone builds allow those packages; overlay users must allow
unfree packages in their own Nixpkgs configuration.

`altserver` currently packages the x86_64 release only.

`darkly-qt5` requires a Nixpkgs version that provides the Qt 5 package. It is
omitted from the standalone outputs when unavailable.

## Use

Install from GitHub and update later:

```sh
nix profile add github:Determinant/nix-packages#darktable
nix profile upgrade --refresh darktable
```

From this checkout:

```sh
nix build path:.#helium
nix run path:.#helium
nix profile add path:.#helium
```

A profile installation from a local path follows that checkout on upgrade;
a GitHub installation follows the repository. Package versions and source hashes
live in `packages/`, including [Helium's release manifest](packages/helium-sources.json).

To use the overlay, add this repository as a flake input and include its
`overlays.default` in `nixpkgs.overlays`. Use the overlay column above to select
packages: for example, `pkgs.darktable-latest` and `pkgs.helium`. The overlay uses
your configuration's Nixpkgs; standalone builds use this repository's `flake.lock`.

## Package notes

### AltServer

```sh
nix build path:.#altserver
nix profile add path:.#altserver
alt-server
```

The `alt-server` command runs the pinned [AltServer Linux NG release](https://github.com/jaakkopalvaila/AltServer-Linux/releases/tag/ng-2026-11-05)
in the foreground. It requires a running Avahi daemon and a device transport
(system usbmuxd for USB, or a separately configured netmuxd for Wi-Fi).
No services or firewall allowances are enabled by installing the package.

The package builds the pinned release source with local reliability fixes. It
keeps profiles for active apps and the app being updated instead of removing all
free-developer profiles before every installation. This avoids deliberately
emptying the developer's profile set; device trust still needs on-device
verification, and changing the signing certificate can still require trust.
CLI installs without an active-app list leave existing profiles in place and let
iOS enforce the usual free-app limit. When AltStore installs an app as inactive
because the active slots are full, the server temporarily removes profiles and
restores the active apps afterwards, including on failed installs. This special
case can still require developer trust. Explicit activation/deactivation and
profile-only refresh requests retain upstream behavior.

The patch also handles partial TCP writes and closed peers, bounds idle reads,
serializes installation progress responses, and recognizes installation errors
on the very first callback. Completion is taken from the installation service's
`Complete` status instead of guessing from a zero-percent progress update. A
stalled installation times out after five minutes without a status callback and
releases the install worker. TCP/USB reads allow up to 60 seconds of inactivity
between chunks. A TCP response has a ten-second send deadline; a failed response
aborts installation and later notifications fail immediately. Device callbacks
hand errors back to the installation task before profile restoration begins.

The Alpine compiler image is pinned by digest and Nix hash and is used only
during the Nix sandbox build through PRoot; Docker is not required. `nix build`
also runs USB/TCP transport tests, installation transaction tests with a mocked
device API, and a daemon protocol/connection-cleanup test. These cover inactive
installs at the app limit, errors before the first progress update, stalled
callbacks, partial profile removal, and repeated installs after failures. The
installed executable is static. Bubblewrap supplies its hardcoded `/etc/ssl/cert.pem` from Nix's CA
bundle and makes `/dev/urandom` usable inside that mount namespace. The wrapper
does not disable certificate verification or modify host `/etc`.
User namespaces must be available. Python and Avahi's DNS-SD library are supplied
by the wrapper for Bonjour advertisement.

The upstream default anisette provider is `https://new.ani.sidestore.io`.
`ALTSERVER_ANISETTE_SERVER` and `ALTSERVER_ANISETTE_PROTOCOL` can override it.
Keep the existing `$XDG_CONFIG_HOME/AltServer/anisette-v3` identity when migrating
an installation (normally `~/.config/AltServer/anisette-v3`). Launch the package
with `alt-server` or `nix run path:.#altserver`.

The server selects a TCP port at startup. The companion `nixos-systems`
`app-firewall altserver` profile tracks that listener and gates it by interface
and source IPv4 network. The tracker checks executable bytes, so the system's
`pkgs.altserver` must be updated together with this patched package before Wi-Fi
connections can reach it. A profile-only upgrade does not update that allowlist.

For a device check, start the updated server, install the same IPA twice from
AltStore, and verify that both attempts finish and the second does not ask to
trust the developer again. Keep the same Apple account, AltStore installation,
and anisette identity during this check. A successful build does not establish
that these device-level symptoms are resolved.

### Helium

Install Helium into your profile or system before creating web apps. Their
launchers use `helium` from `PATH`, so they keep working across upgrades.
The package keeps the browser's sandbox and update notifications enabled.

Set extra browser flags through an override:

```nix
pkgs.helium.override {
  commandLineArgs = [ "--ozone-platform=wayland" ];
}
```

### Morgen

The wrapper runs Morgen on X11 and supplies a KDE autostart entry. It disables
Morgen's own autostart entry before launch and on exit, including failed exits.

If Chromium unloads GTK modules needed by your KDE desktop, keep them loaded with:

```nix
pkgs.ted-morgen.override {
  gtkModules = [
    "colorreload-gtk-module"
    "window-decorations-gtk-module"
  ];
}
```

The modules must be available through `GTK_PATH`. Without this override, the
wrapper preserves the existing `GTK_MODULES` value.

### Brother scan-to-PC

Import `nixosModules.brscan-skey` alongside the overlay. The module enables SANE
support and installs a user service. Start it with:

```sh
systemctl --user start brscan-skey.service
```

The daemon discovers the scanner on the network and keeps writable vendor
configuration under `~/.local/state/brscan-skey`. Its module options are
`ted.brscanSkey.enable` (enabled on import) and `ted.brscanSkey.package`.

### Discord

The package backports the [KDE Wayland scaling fix](https://github.com/NixOS/nixpkgs/pull/552157)
when it is missing from the selected Nixpkgs. The fix adds
`--force-device-scale-factor=1` on KDE Wayland to avoid applying DPI scaling twice.
Fully quit Discord and reopen it after installing the package.

## Development

`packages/` holds package definitions and the Helium manifest, `modules/` holds
NixOS modules, `scripts/` holds the updater, and `tests/` holds package checks.
CI workflows live in `.github/workflows/`.

Use the formatter pinned by the flake. Keep Nix indentation at two spaces and
prefer explicit library references such as `lib.licenses.gpl3Plus`.

```sh
nix fmt
nix fmt -- --ci
nix flake check --no-build --all-systems path:.
```

The second command fails if formatting changes are needed. The last command
evaluates the flake for both architectures without building the checks.

Run the package checks individually:

```sh
nix build path:.#checks.x86_64-linux.morgen-wrapper
nix build path:.#checks.x86_64-linux.altserver
nix build path:.#checks.x86_64-linux.brscan-skey
nix build --out-link result-helium path:.#checks.x86_64-linux.helium
python3 tests/helium_smoke.py ./result-helium/bin/helium
python3 -m unittest discover -s tests -p test_helium_updater.py
```

The Morgen check uses a fake app to test launcher arguments, environment, exit
status, and autostart cleanup. The Brother VM test uses fake discovery and a fake
vendor executable, but exercises the real module, SANE registration, and
Bubblewrap with a root-owned mode-0711 `/opt`.

Helium's build checks its version, desktop entry, and GTK printing libraries.
The separate headless test checks rendering, JavaScript, storage, and the
browser's reported namespace/seccomp sandbox status. It uses a temporary profile
and runs outside Nix's build sandbox. Graphics, audio, web app installation,
physical printing, and physical scanning need manual testing.

## Updates and CI

Update Helium or the shared Nixpkgs pin with:

```sh
python3 scripts/update-helium.py
nix flake update nixpkgs
```

The Helium updater accepts `--version` followed by a release tag. It hashes both
Linux downloads, compares them with GitHub's SHA-256 digests when provided, and
replaces the manifest only after both architectures succeed. An unchanged entry
with a matching GitHub digest is reused. Set `GH_TOKEN` or `GITHUB_TOKEN` if needed
for API rate limits.

The [Nix workflow](.github/workflows/nix.yml) checks formatting and evaluates both
architectures on every push and pull request. The [Helium workflow](.github/workflows/helium.yml)
also builds and runs Helium on both architectures when its package, tests,
updater, workflow, or flake files change. It checks for releases daily and Nixpkgs
updates weekly, opening separate `update-helium` and `update-nixpkgs` PRs after
validation. These PRs are not merged automatically.

Other packages are evaluated but not built by these workflows. Review changes to
`flake.lock` for their effect on the whole package set.
