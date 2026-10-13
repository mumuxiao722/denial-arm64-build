# Small host-specific build. The raw input remains identical across Nixpkgs hosts.
{
  lib,
  denialSource,
  stdenvNoCC,
  autoPatchelfHook,
  patchelf,
  python3,
  runCommand,
  fontconfig,
  gtk3,
  stdenv,
  rawEngine,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "denial-flutter-engine";
  version = rawEngine.sourceEngine.version;
  src = rawEngine;
  nativeBuildInputs = [
    autoPatchelfHook
    patchelf
    python3
  ];
  buildInputs = [
    fontconfig
    gtk3
    (lib.getLib stdenv.cc.cc)
  ];
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    python3 ${./engine-manifest.py} verify . \
      --source-lock ${denialSource}/prebuilt/flutter-engine/SOURCE_LOCK.json} \
      --nix-lock ${./flutter-engine-lock.json} --platform ${stdenv.hostPlatform.system} \
      --minimum-glibc ${rawEngine.minimumGlibc} \
      --minimum-compiler-runtime ${rawEngine.minimumCompilerRuntime} \
      --nixpkgs-version ${lib.escapeShellArg rawEngine.producerNixpkgsVersion}
    mkdir -p $out
    cp -R . $out/
    chmod -R u+w $out
    runHook postInstall
  '';
  passthru = {
    inherit rawEngine;
    inherit (rawEngine) sourceLockSha256 minimumGlibc;
    nativeLibc = stdenv.cc.libc;
    buildStrategy = "cached-engine";
    runtimeMode = "release";
    outName = "host_release";
    isOptimized = true;
    dartSdkVersion = rawEngine.sourceEngine.dartSdkVersion;
    dart =
      runCommand "denial-engine-dart-sdk-${rawEngine.sourceEngine.dartSdkVersion}"
        {
          version = rawEngine.sourceEngine.dartSdkVersion;
          meta = {
            mainProgram = "dart";
            platforms = [ "x86_64-linux" "aarch64-linux" ];
          };
        }
        ''
          ln -s ${finalAttrs.finalPackage}/out/host_release/dart-sdk $out
        '';
    release = finalAttrs.finalPackage;
  };
  meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
})
