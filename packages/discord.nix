{
  pkgs,
  package ? pkgs.discord,
}:
let
  source = pkgs.path + "/pkgs/applications/networking/instant-messengers/discord";
  hasScalingFix = pkgs.lib.hasInfix "discordKdeWayland" (builtins.readFile (source + "/linux.nix"));
  patchedSource = pkgs.applyPatches {
    src = source;
    patches = [
      (pkgs.fetchpatch {
        # https://github.com/NixOS/nixpkgs/pull/552157
        url = "https://github.com/NixOS/nixpkgs/commit/1313b4a16fe102bbbbee93e42c20dc8c8ecc0824.patch";
        relative = "pkgs/applications/networking/instant-messengers/discord";
        hash = "sha256-1nKtIKZpsoR9X7DmRgn47iQVSrOOyxf8OhYG26RAqrg=";
      })
    ];
  };
in
if hasScalingFix then package else (pkgs.callPackage patchedSource { }).discord
