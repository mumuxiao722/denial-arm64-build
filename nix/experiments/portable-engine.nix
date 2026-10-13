# Experimental host adaptation of a verified, already-built release engine.
# This does not change the module default or authorize unverified engine inputs.
{
  pkgs,
  denialSource,
  engineRoot,
  bundle,
  embedderHeader,
  expectedEngineSha256,
  dartSdk ? null,
  sourceLock ? denialSource + "/prebuilt/flutter-engine/SOURCE_LOCK.json",
}:
let
  rawEngine = builtins.path {
    path = engineRoot;
    name = "denial-portable-engine-raw";
  };
  rawBundle = builtins.path {
    path = bundle;
    name = "denial-portable-shell-raw";
  };
  engine = pkgs.stdenvNoCC.mkDerivation {
    pname = "denial-portable-engine-experiment";
    version = "0";
    src = rawEngine;
    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.patchelf
    ];
    buildInputs = [
      pkgs.fontconfig
      pkgs.gtk3
      (pkgs.lib.getLib pkgs.stdenv.cc.cc)
    ];
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall
      echo '${expectedEngineSha256}  out/host_release/libflutter_engine.so' | sha256sum -c -
      mkdir -p $out
      cp -R . $out/
      chmod -R u+w $out
      ${pkgs.lib.optionalString (dartSdk != null) ''
        ln -s ${dartSdk} $out/out/host_release/dart-sdk
      ''}
      # Existing Nix engine outputs can retain their original RUNPATH. Remove
      # it on copies before autoPatchelf selects the host's dependencies.
      while IFS= read -r -d "" file; do
        if patchelf --print-rpath "$file" >/dev/null 2>&1; then
          patchelf --remove-rpath "$file"
        fi
      done < <(find $out -type f -print0)
      runHook postInstall
    '';
    passthru = {
      inherit rawEngine expectedEngineSha256;
      sourceLockSha256 = builtins.hashFile "sha256" sourceLock;
      runtimeMode = "release";
      outName = "host_release";
      isOptimized = true;
    };
    meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
  runtime = pkgs.runCommand "denial-portable-runtime-experiment" { } ''
    cp -R ${rawBundle} $out
    chmod -R u+w $out
    cp ${engine}/out/host_release/libflutter_engine.so $out/lib/libflutter_engine.so
  '';
  probe = pkgs.stdenv.mkDerivation {
    pname = "denial-portable-engine-probe";
    version = "0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.libgbm
      pkgs.libglvnd
    ];
    buildPhase = ''
      cp ${embedderHeader} flutter_embedder.h
      $CC -std=c11 -Wall -Wextra -Werror -O2 -I. \
        ${../tests/engine-probe.c} -o probe \
        $(pkg-config --cflags --libs gbm egl glesv2) -ldl
    '';
    installPhase = ''
      install -Dm755 probe $out/bin/denial-portable-engine-probe
    '';
  };
in
{
  inherit engine runtime probe;
  identity = {
    rawEngine = toString rawEngine;
    inherit expectedEngineSha256;
    adaptedEngine = toString engine;
    hostLibc = toString pkgs.stdenv.cc.libc;
    hostLibcVersion = pkgs.stdenv.cc.libc.version;
  };
}
