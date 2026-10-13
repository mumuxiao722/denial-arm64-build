{
  # AArch64 port: the fork of this directory no longer sits beside upstream's
  # source tree, so the paths its files reach for are passed in rather than
  # resolved as ../. denialSource is also published as a package set attribute,
  # which is how callPackage hands it to every file that declares it.
  denialSource,
  src ? denialSource,
  version ? "0.0.0+unknown",
  buildIdentity ? "nix.unknown",
  sourceRevision ? "unknown",
  flutterNixpkgs ? null,
  pluginCollection ? null,
}:

final: _prev:
let
  cleanSrc = final.lib.cleanSourceWith {
    name = "source";
    inherit src;
    filter =
      path: type:
      let
        name = baseNameOf (toString path);
      in
      !(
        type == "directory"
        && builtins.elem name [
          ".dart_tool"
          ".git"
          "build"
          "out"
          "profiling"
          "target"
        ]
      )
      && name != "libflutter_engine.so";
  };
in
{
  inherit denialSource;

  denialFlutter = final.callPackage ./flutter-engine.nix (
    final.lib.optionalAttrs (flutterNixpkgs != null) { inherit flutterNixpkgs; }
  );
  denialFlutterSource = final.callPackage ./flutter-engine.nix (
    {
      buildEngineFromSource = true;
    }
    // final.lib.optionalAttrs (flutterNixpkgs != null) { inherit flutterNixpkgs; }
  );
  denial = final.callPackage ./package.nix {
    src = cleanSrc;
    inherit version buildIdentity sourceRevision;
    taskbarSrc =
      if pluginCollection == null then null else pluginCollection + "/plugins/denial_taskbar";
  };
  denialPluginManager = final.denial.pluginManager;
}
