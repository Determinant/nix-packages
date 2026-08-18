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
          pkgs = import nixpkgs { inherit system; };
          darktable = pkgs.callPackage ./packages/darktable.nix { };
        in
        {
          inherit darktable;
          darktable-ai = darktable.override { withAi = true; };
          default = darktable;
        };
    in
    {
      packages = forAllSystems mkPackages;

      overlays.default = final: _prev: let
        darktable-latest = final.callPackage ./packages/darktable.nix { };
      in
      {
        inherit darktable-latest;
        darktable-latest-ai = darktable-latest.override { withAi = true; };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
