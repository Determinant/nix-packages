{
  description = "Personal Nix packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      unfreePackageNames = [
        "brscan-skey"
        "brscan4"
        "brscan5"
        "brother-udev-rule-type1"
        "google-chrome"
        "morgen"
        "ted-google-chrome"
        "ted-morgen"
        "ted-neroaac-bin"
      ];
      mkPackages =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate =
              package: builtins.elem (nixpkgs.lib.getName package) unfreePackageNames;
          };
          darktable = pkgs.callPackage ./packages/darktable.nix { };
          darklyQt5 = builtins.tryEval pkgs.darkly-qt5;
          mkDarkly =
            package:
            import ./packages/darkly.nix {
              inherit package;
              inherit (pkgs) fetchFromGitHub;
            };
        in
        {
          inherit darktable;
          helium = pkgs.callPackage ./packages/helium.nix { };
          darkly = mkDarkly pkgs.darkly;
          darkly-gtk = pkgs.callPackage ./packages/darkly-gtk.nix { };
          darktable-ai = darktable.override { withAi = true; };
          ted-ortho4xp-deps = pkgs.callPackage ./packages/ortho4xp-deps.nix { };
          default = darktable;
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          brscan-skey = pkgs.callPackage ./packages/brscan-skey.nix { };
          ted-google-chrome = pkgs.callPackage ./packages/google-chrome-wrapper.nix { };
          ted-morgen = pkgs.callPackage ./packages/morgen-wrapper.nix { };
          ted-neroaac-bin = pkgs.callPackage ./packages/neroaac-bin.nix { };
        }
        // pkgs.lib.optionalAttrs darklyQt5.success {
          darkly-qt5 = mkDarkly darklyQt5.value;
        };
    in
    {
      packages = forAllSystems mkPackages;

      checks = forAllSystems (system: {
        helium = self.packages.${system}.helium;
      });

      overlays.default =
        final: prev:
        let
          darktable-latest = final.callPackage ./packages/darktable.nix { };
          mkDarkly =
            package:
            import ./packages/darkly.nix {
              inherit package;
              inherit (final) fetchFromGitHub;
            };
        in
        {
          inherit darktable-latest;
          helium = final.callPackage ./packages/helium.nix { };
          darkly = mkDarkly prev.darkly;
          darkly-qt5 = mkDarkly prev.darkly-qt5;
          darkly-gtk = final.callPackage ./packages/darkly-gtk.nix { };
          darktable-latest-ai = darktable-latest.override { withAi = true; };
          ted-ortho4xp-deps = final.callPackage ./packages/ortho4xp-deps.nix { };
        }
        // prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-linux") {
          brscan-skey = final.callPackage ./packages/brscan-skey.nix { };
          ted-google-chrome = final.callPackage ./packages/google-chrome-wrapper.nix { };
          ted-morgen = final.callPackage ./packages/morgen-wrapper.nix { };
          ted-neroaac-bin = final.callPackage ./packages/neroaac-bin.nix { };
        };

      nixosModules.brscan-skey = import ./modules/brscan-skey.nix;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
