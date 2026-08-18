{
  package,
  fetchFromGitHub,
}:
let
  version = "0.5.37";
in
package.overrideAttrs (_: {
  inherit version;
  src = fetchFromGitHub {
    owner = "Bali10050";
    repo = "Darkly";
    tag = "v${version}";
    hash = "sha256-6q2+HSOh3ZWLBnBkaKVgAuJJlHF+ny1bI6zatZaj+x0=";
  };
})
