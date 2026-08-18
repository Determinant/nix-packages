{
  lib,
  pkgs,
}:
let
  get = path: lib.attrByPath path null pkgs;
  pythonModuleNames = [
    "numpy"
    "scipy"
    "requests"
    "pillow"
    "shapely"
    "pyproj"
    "rtree"
    "gdal"
  ];
  pythonRuntime = pkgs.python3.withPackages (
    ps:
    builtins.filter (package: package != null) (
      map (name: lib.attrByPath [ name ] null ps) pythonModuleNames
    )
  );
  runtimeDependencies = builtins.filter (package: package != null) [
    pythonRuntime
    (get [ "gdal" ])
    (get [ "proj" ])
    (get [ "osmium-tool" ])
    (get [ "nvidia-texture-tools" ])
  ];
in
pkgs.buildEnv {
  name = "ted-ortho4xp-deps";
  paths = runtimeDependencies;
  ignoreCollisions = true;
}
