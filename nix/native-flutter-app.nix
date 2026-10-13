{ lib, denialFlutter, nativeApp, stdenv }:
{ name, app, src, pubspecLock, sourceLockHash, version, postInstall ? "" }:
let
  targetPlatform =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "Denial does not support ${stdenv.hostPlatform.system}");
in
assert lib.assertMsg (pubspecLock.source_sha256 == sourceLockHash)
  "${app}/pubspec.lock changed; run tools/denial-nix refresh-pub-locks";
denialFlutter.buildFlutterApplication {
  pname = name;
  inherit version src pubspecLock;
  sourceRoot = "source/${app}";
  flutterMode = "release";
  dontUseCmakeConfigure = true;
  buildPhase = ''
    runHook preBuild
    flutter assemble --local-engine host_release --suppress-analytics \
      --output=build/nix-assembly -dTargetFile=lib/main.dart -dBuildMode=release \
      -dTargetPlatform=${targetPlatform} -dDartObfuscation=false \
      -dTrackWidgetCreation=true -dTreeShakeIcons=true release_bundle_${targetPlatform}_assets
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    bundle="$out/app/${name}"
    install -d "$bundle/data/flutter_assets" "$bundle/lib" $out/bin $debug
    cp -R build/nix-assembly/flutter_assets/. "$bundle/data/flutter_assets/"
    install -m755 build/nix-assembly/lib/libapp.so "$bundle/lib/libapp.so"
    install -m644 ${denialFlutter.engine}/out/host_release/icudtl.dat "$bundle/data/icudtl.dat"
    install -m755 ${denialFlutter.engine}/out/host_release/libflutter_engine.so "$bundle/lib/libflutter_engine.so"
    install -m755 ${nativeApp}/bin/denial-app "$bundle/${name}"
    ln -s "$bundle/${name}" "$out/bin/${name}"
    runHook postInstall
  '';
  inherit postInstall;
  doInstallCheck = true;
  installCheckPhase = ''
    test -x $out/app/${name}/${name}
    test -f $out/app/${name}/data/flutter_assets/AssetManifest.bin
    test -x $out/app/${name}/lib/libapp.so
    test -x $out/app/${name}/lib/libflutter_engine.so
  '';
  meta = {
    description = "Native Flutter ${name} application";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
