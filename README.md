# nix-packages

Personal Nix packages, exposed as standalone flake packages and through the
default overlay.

## Available packages

- `darktable` and `darktable-ai`
- `darkly`, `darkly-qt5`, and `darkly-gtk`
- `ted-neroaac-bin`
- `ted-ortho4xp-deps`

`darkly-qt5` is available through the overlay when the consumer's nixpkgs still
provides the underlying Qt 5 package, including NixOS 25.11.

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
