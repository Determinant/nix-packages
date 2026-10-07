# nix-packages

Personal Nix packages, exposed as standalone flake packages and through the
default overlay.

## Available packages

- `darktable` and `darktable-ai`
- `helium`
- `darkly`, `darkly-qt5`, and `darkly-gtk`
- `brscan-skey`
- `ted-google-chrome` and `ted-morgen`
- `ted-neroaac-bin`
- `ted-ortho4xp-deps`

`darkly-qt5` is available through the overlay when the consumer's nixpkgs still
provides the underlying Qt 5 package, including NixOS 25.11.

`brscan-skey`, `ted-google-chrome`, `ted-morgen`, and `ted-neroaac-bin` are
available on x86_64 Linux only. These packages contain unfree software.

The default overlay provides every package attribute. The Brscan package also
has a NixOS integration module at `nixosModules.brscan-skey`; consumers should
apply the default overlay before importing the module.

## darktable

The default package is darktable 5.6.0, the latest stable upstream release. The
normal output excludes the optional ONNX Runtime dependency; an AI-enabled
variant is also available.

Build locally:

```sh
nix build path:.#darktable
```

Install locally into the current user's Nix profile:

```sh
nix profile add path:.#darktable
```

Install from GitHub:

```sh
nix profile add github:Determinant/nix-packages#darktable
```

Use `#darktable-ai` instead of `#darktable` to enable darktable's optional AI
subsystem. Update the profile later with:

```sh
nix profile upgrade darktable
```

## Helium

`helium` packages the official stable Linux release binaries for x86_64 and
ARM64. The release URLs and SHA-256 hashes are pinned in
`packages/helium-sources.json`; the package does not depend on another community
Helium flake. It is also available as `pkgs.helium` through the default overlay.

Build or run from this checkout:

```sh
nix build path:.#helium
nix run path:.#helium
```

Install this checkout into your user profile:

```sh
nix profile add path:/home/ymf/setup/nix-packages#helium
```

Once published to GitHub, install with:

```sh
nix profile add github:Determinant/nix-packages#helium
```

Use one of these installation sources. Update later with
`nix profile upgrade --refresh helium`; a local installation follows this
checkout, while a GitHub installation follows the published repository.

The package installs the upstream desktop entry and icon, includes the XDG
utilities used by web app installation, and sets `CHROME_WRAPPER=helium` so
generated PWA launchers use the profile's executable rather than a particular
Nix store version. Install Helium into your profile or system before creating
PWAs so `helium` remains available on your desktop session's `PATH`.
Full GUI/PWA behavior still needs testing in your desktop environment.

Additional flags can be supplied with
`pkgs.helium.override { commandLineArgs = [ "--ozone-platform=wayland" ]; }`.
The package preserves the browser's default sandbox and update notifications.
Only the Qt 6 integration shim is shipped; dependency checks have no Qt 5
exceptions.

Update to the latest official stable release, or select a version explicitly:

```sh
python3 scripts/update-helium.py
python3 scripts/update-helium.py --version 0.18.3.1
nix build path:.#checks.x86_64-linux.helium
```

Run the runtime check after building:

```sh
nix build --out-link result-helium path:.#helium
python3 tests/helium_smoke.py ./result-helium/bin/helium
```

This checks rendering, JavaScript, local storage, and the browser's reported
namespace/seccomp sandbox status using a temporary profile and cache. It runs
outside Nix's build sandbox, where the browser can create its own namespaces.
GPU acceleration is disabled for this headless check; graphics, audio, and interactive PWA
installation still need desktop testing.

The updater verifies both downloaded assets against GitHub's published SHA-256
digests when provided, and replaces the manifest only after both succeed. It
accepts `GH_TOKEN` or `GITHUB_TOKEN` for API rate limits. These checksums provide
integrity checking, not independent signature verification.

The Helium GitHub Actions workflow checks daily for releases and weekly for
Nixpkgs updates. Release updates use an `update-helium` PR; shared dependency
updates use a separate `update-nixpkgs` PR. Manual workflow runs can select
"Refresh Nixpkgs"; locally, use `nix flake update nixpkgs`.

Both update paths evaluate all flake outputs, build Helium, check its version and
desktop file, and run the runtime smoke test on both Linux architectures before
opening a PR. Relevant pushes and PRs run the same checks. The Ubuntu CI runners
use a temporary AppArmor rule scoped to the tested browser binary to allow its
sandbox; this does not change the package's behavior on NixOS.

Because `flake.lock` is shared, review dependency PRs for effects on the other
packages too. Those packages are evaluated by CI, but only Helium is built and
run by this workflow.

The workflow becomes active after publication on the default branch; enable
"Allow GitHub Actions to create and approve pull requests" in repository Actions
settings so it can open PRs. Updates are not merged automatically.
