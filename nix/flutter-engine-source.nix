# Source builder shared by the pinned cache producer and host-source fallback.
{
  lib,
  denialSource,
  pkgs,
  stdenv,
  fetchurl,
  flutterNixpkgs ? pkgs.path,
  maintenanceOnly ? false,
}:
let
  sourceLock = lib.importJSON (denialSource + "/prebuilt/flutter-engine/SOURCE_LOCK.json");
  nixLock = lib.importJSON ./flutter-engine-lock.json;
  sourceLockHash = builtins.hashFile "sha256" (denialSource + "/prebuilt/flutter-engine/SOURCE_LOCK.json");
  flutterVersion = "3.47.5";
  flutterRevision = sourceLock.flutter.revision;
  engineVersion = lib.removeSuffix "\n" (
    builtins.readFile (denialSource + "/prebuilt/flutter-engine/linux-x64-release/ENGINE_REVISION")
  );
  dartVersion = nixLock.dart.version;
  flutterNix = flutterNixpkgs + "/pkgs/development/compilers/flutter";
  # AArch64 port. Upstream keys these by system with a throw as the fallback,
  # which is why packages.aarch64-linux did not exist rather than failing to
  # build: there was no hash to put in the table.
  dartHash =
    {
      x86_64-linux = nixLock.dart.hash;
      aarch64-linux = nixLock.dart.hash_aarch64;
    }
    .${stdenv.hostPlatform.system}
      or (throw "Denial Flutter does not support ${stdenv.hostPlatform.system}");

  # The archive is named after the target, not the version.
  dartArchive =
    {
      x86_64-linux = "dartsdk-linux-x64-release.zip";
      aarch64-linux = "dartsdk-linux-arm64-release.zip";
    }
    .${stdenv.hostPlatform.system}
      or (throw "Denial Flutter does not support ${stdenv.hostPlatform.system}");

  dart = pkgs.dart-bin.overrideAttrs (_: {
    version = dartVersion;
    src = fetchurl {
      url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${dartVersion}/sdk/${dartArchive}";
      hash = dartHash;
    };
  });

  engineTools = pkgs.callPackage (flutterNix + "/engine/tools.nix") {
    inherit (stdenv) hostPlatform buildPlatform;
    depot_toolsCommit = sourceLock.depot_tools.revision;
    depot_toolsHash = nixLock.depot_tools.hash;
  };
  enginePackageCallPackage =
    path: args:
    pkgs.callPackage path (
      args
      // lib.optionalAttrs (toString path == flutterNix + "/engine/source.nix") {
        tools = engineTools;
      }
    );
  engineCallPackage =
    path: args:
    let
      isEnginePackage = toString path == flutterNix + "/engine/package.nix";
      package = pkgs.callPackage path (
        args
        // {
          inherit dart;
        }
        // lib.optionalAttrs isEnginePackage {
          tools = engineTools;
          callPackage = enginePackageCallPackage;
        }
      );
    in
    if isEnginePackage then
      package.overrideAttrs (oldAttrs: {
        # Retain the actual configuration for the raw artifact's manifest.
        preInstall = (oldAttrs.preInstall or "") + ''
          cp $out/out/host_release/args.gn $out/denial-args.gn
        '';
        configureFlags = (oldAttrs.configureFlags or [ ]) ++ [
          "--slimpeller"
          "--gn-args=shell_enable_vulkan=false"
          "--gn-args=test_enable_vulkan=false"
          "--gn-args=skia_use_vulkan=false"
        ];
      })
    else
      package;
  flutterCallPackage =
    path: args:
    pkgs.callPackage path (
      args
      // lib.optionalAttrs (toString path == flutterNix + "/engine/default.nix") {
        # Nixpkgs passes the requested Dart version into engine/default.nix but
        # does not forward the matching bootstrap SDK to engine/package.nix.
        callPackage = engineCallPackage;
      }
    );
  rawEngine = flutterCallPackage (flutterNix + "/engine/default.nix") {
    dartSdkVersion = dart.version;
    inherit flutterVersion;
    swiftshaderRev = nixLock.swiftshader.revision;
    swiftshaderHash = nixLock.swiftshader.hash;
    version = engineVersion;
    hashes = {
      x86_64-linux.x86_64-linux = nixLock.engine.source_hash;
      aarch64-linux.aarch64-linux = nixLock.engine.source_hash_aarch64;
    };
    url = "${sourceLock.flutter.repository}@${flutterRevision}";
    patches = [ ];
    runtimeModes = [
      "release"
      "release"
    ];
  };
in
assert lib.assertMsg (
  maintenanceOnly
  || (
    nixLock.schema_version == 1
    && nixLock.source_lock_sha256 == sourceLockHash
    && nixLock.flutter.revision == flutterRevision
    && nixLock.skia.revision == sourceLock.skia.revision
    && nixLock.depot_tools.revision == sourceLock.depot_tools.revision
    && nixLock.engine.revision == engineVersion
  )
) "Engine source locks differ; run tools/denial-nix refresh-engine-lock";
rawEngine.overrideAttrs (oldAttrs: {
  runtimeModes = [ "release" ];
  altRuntimeMode = "release";
  installPhase = ''
    runHook preInstall
    mkdir --parents $out/out
    ln --symbolic ${rawEngine.release}/out/${rawEngine.release.outName} \
      $out/out/${rawEngine.release.outName}
    runHook postInstall
  '';
  passthru = oldAttrs.passthru // {
    sourceLockSha256 = sourceLockHash;
    depotToolsSource = engineTools.depot_tools;
    nativeLibc = stdenv.cc.libc;
    buildStrategy = "host-source";
  };
})
