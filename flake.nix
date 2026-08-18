{
  description = "Personal Nix packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      mkPackages =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = package:
              nixpkgs.lib.getName package == "ted-neroaac-bin";
          };
          darktable = pkgs.callPackage ./packages/darktable.nix { };
          darklyQt5 = builtins.tryEval pkgs.darkly-qt5;
          mkDarkly = package:
            import ./packages/darkly.nix {
              inherit package;
              inherit (pkgs) fetchFromGitHub;
            };
        in
        {
          inherit darktable;
          darkly = mkDarkly pkgs.darkly;
          darkly-gtk = pkgs.callPackage ./packages/darkly-gtk.nix { };
          darktable-ai = darktable.override { withAi = true; };
          ted-neroaac-bin = pkgs.callPackage ./packages/neroaac-bin.nix { };
          ted-ortho4xp-deps = pkgs.callPackage ./packages/ortho4xp-deps.nix { inherit pkgs; };
          default = darktable;
        }
        // pkgs.lib.optionalAttrs darklyQt5.success {
          darkly-qt5 = mkDarkly darklyQt5.value;
        };
    in
    {
      packages = forAllSystems mkPackages;

      overlays.default = final: prev:
        let
          darktable-latest = final.callPackage ./packages/darktable.nix { };
          mkDarkly = package:
            import ./packages/darkly.nix {
              inherit package;
              inherit (final) fetchFromGitHub;
            };
        in
        {
          inherit darktable-latest;
          darkly = mkDarkly prev.darkly;
          darkly-qt5 = mkDarkly prev.darkly-qt5;
          darkly-gtk = final.callPackage ./packages/darkly-gtk.nix { };
          darktable-latest-ai = darktable-latest.override { withAi = true; };
          ted-neroaac-bin = final.callPackage ./packages/neroaac-bin.nix { };
          ted-ortho4xp-deps = final.callPackage ./packages/ortho4xp-deps.nix { pkgs = final; };
        };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
