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
