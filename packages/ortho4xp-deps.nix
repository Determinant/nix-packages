{
  lib,
  buildEnv,
  python3,
  gdal ? null,
  proj ? null,
  osmium-tool ? null,
  nvidia-texture-tools ? null,
}:
let
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
  pythonRuntime = python3.withPackages (
    ps:
    builtins.filter (package: package != null) (
      map (name: lib.attrByPath [ name ] null ps) pythonModuleNames
    )
  );
  runtimeDependencies = builtins.filter (package: package != null) [
    pythonRuntime
    gdal
    proj
    osmium-tool
    nvidia-texture-tools
  ];
in
buildEnv {
  name = "ted-ortho4xp-deps";
  paths = runtimeDependencies;
  ignoreCollisions = true;
}
