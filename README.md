# nix-packages

Personal Nix packages, exposed as a flake.

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
nix profile install path:.#darktable
```

After publishing this repository to GitHub:

```sh
nix profile install github:Determinant/nix-packages#darktable
```

Use `#darktable-ai` instead of `#darktable` to enable darktable's optional AI
subsystem. Update the profile later with:

```sh
nix profile upgrade darktable
```
