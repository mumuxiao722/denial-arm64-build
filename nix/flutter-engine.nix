{
  lib,
  denialSource,
  pkgs,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  fetchzip,
  runCommand,
  flutterNixpkgs ? pkgs.path,
  maintenanceOnly ? false,
  # Retained for the isolated lab probe; normal packages use the pinned producer.
  releaseEngineOverride ? null,
  buildEngineFromSource ? false,
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

  bootstrapDart = pkgs.dart-bin.overrideAttrs (_: {
    version = dartVersion;
    src = fetchurl {
      url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${dartVersion}/sdk/${dartArchive}";
      hash = dartHash;
    };
  });

  fetchedFlutter = fetchFromGitHub {
    owner = "denialwm";
    repo = "flutter";
    rev = flutterRevision;
    hash = nixLock.flutter.hash;
  };
  materialFonts = fetchzip {
    url = "https://storage.googleapis.com/flutter_infra_release/flutter/fonts/${nixLock.material_fonts.revision}/fonts.zip";
    hash = nixLock.material_fonts.hash;
    stripRoot = false;
  };

  # Flutter expects these cache markers even when the engine is supplied by
  # Nix. Keep the fetched source immutable and add only the generated markers.
  flutterSource = runCommand "denial-flutter-${flutterVersion}-source" { } ''
    cp --recursive ${fetchedFlutter} $out
    chmod --recursive u+w $out/bin
    mkdir --parents $out/bin/cache
    cp $out/bin/internal/engine.version $out/bin/cache/engine.stamp
    mkdir --parents $out/bin/cache/artifacts
    cp --recursive ${materialFonts} $out/bin/cache/artifacts/material_fonts
    cp $out/bin/internal/material_fonts.version $out/bin/cache/material_fonts.stamp
    touch $out/bin/cache/engine.realm
    actual_pubspec_hash="$(sha256sum $out/packages/flutter_tools/pubspec.yaml | cut -d ' ' -f 1)"
    test "$actual_pubspec_hash" = '${pubspecLock.source_pubspec_sha256}' || {
      echo 'Flutter tools pubspec.yaml changed without regenerating nix/flutter-pubspec-lock.json' >&2
      echo 'run `tools/denial-nix refresh-pub-locks`' >&2
      exit 1
    }
  '';

  # Pin helper definitions independently of the native package set. Calling
  # them through the host's pkgs keeps libc and graphics dependencies aligned
  # with the drivers loaded from /run/opengl-driver, even on NixOS unstable.
  flutterNix = flutterNixpkgs + "/pkgs/development/compilers/flutter";
  mkCustomFlutter = pkgs.callPackage (flutterNix + "/flutter.nix");
  # These stay in the locked helper source rather than a downstream patch
  # series in this tree.
  frameworkPatches = map (name: flutterNix + "/patches/${name}") [
    "copy-without-perms.patch"
    "do-not-log-os-release-read-failure.patch"
    "dont-validate-executable-location.patch"
    "flutter-pub-dart-override.patch"
    "override-host-platform.patch"
    "override-operating-system.patch"
  ];

  versionPatches = map (name: flutterNix + "/versions/3_41/patches/${name}") [
    "disable-auto-update.patch"
    "deregister-pub-dependencies-artifact.patch"
  ];

  sourceEngine = pkgs.callPackage ./flutter-engine-source.nix {
    inherit flutterNixpkgs maintenanceOnly;
  };
  # Never import the consumer's overlays or native overrides into the producer.
  # Its derivation stays identical when the host Nixpkgs changes.
  enginePkgs = import flutterNixpkgs { system = stdenv.hostPlatform.system; };
  pinnedRawEngine = enginePkgs.callPackage ./flutter-engine-raw.nix {
    inherit flutterNixpkgs;
  };
  hostSupportsPinnedEngine = import ./engine-compatible.nix {
    inherit lib;
    libcVersion = stdenv.cc.libc.version;
    compilerVersion = stdenv.cc.cc.version;
    isGNU = stdenv.cc.isGNU or false;
    inherit (pinnedRawEngine) minimumGlibc minimumCompilerRuntime;
  };
  usePinnedEngine = !buildEngineFromSource && hostSupportsPinnedEngine;
  releaseEngine =
    if releaseEngineOverride != null then
      releaseEngineOverride
    else if usePinnedEngine then
      pkgs.callPackage ./flutter-engine-adapt.nix {
        rawEngine = pinnedRawEngine;
      }
    else
      sourceEngine;
  # Compiler snapshots and platform kernels require the exact SDK hash, not
  # just the same Dart version. Keep the source-built SDK with its engine.
  dart = releaseEngine.dart or bootstrapDart;
  # Application compilation only needs the locked Flutter GPU declarations.
  applicationEngineSource = runCommand "denial-engine-source-projection" { } ''
    mkdir -p $out/src
    ln -s ${fetchedFlutter}/engine/src/flutter $out/src/flutter
  '';

  # Lock maintenance must remain evaluable after SOURCE_LOCK.json advances and
  # before the Flutter application lock has been regenerated. In particular,
  # none of these fetchers may cross the application-only assertions below.
  maintenanceSources = {
    inherit fetchedFlutter;
    dart = bootstrapDart;
    depotToolsSource = sourceEngine.depotToolsSource;
    engineSource = sourceEngine.src;
  };

  pubspecLock = lib.importJSON ./flutter-pubspec-lock.json;
  flutterPub2Nix = pkgs.pub2nix // {
    readPubspecLock =
      args:
      pkgs.pub2nix.readPubspecLock (
        args
        // {
          gitHashes = {
            assets_for_android_views = "sha256-GN7nBxBwnlByp3E8uUDabWiuMUoYYHPtIveF+RiEpS8=";
          }
          // (args.gitHashes or { });
          sdkSourceBuilders = (args.sdkSourceBuilders or { }) // {
            flutter =
              name:
              runCommand "flutter-sdk-${name}" { passthru.packageRoot = "."; } ''
                for source in \
                  ${flutterSource}/packages/${name} \
                  ${releaseEngine}/out/${releaseEngine.outName}/gen/dart-pkg/${name}; do
                  if [ -d "$source" ]; then
                    ln --symbolic "$source" $out
                    exit 0
                  fi
                done
                echo "Flutter SDK package is unavailable: ${name}" >&2
                exit 1
              '';
          };
        }
      );
  };
  flutterBuildDartApplication = pkgs.buildDartApplication.override {
    pub2nix = flutterPub2Nix;
  };
  flutterTools = pkgs.callPackage (flutterNix + "/flutter-tools.nix") {
    inherit dart pubspecLock;
    buildDartApplication = flutterBuildDartApplication;
    version = flutterVersion;
    flutterSrc = flutterSource;
    patches = frameworkPatches ++ versionPatches;
    systemPlatform = stdenv.hostPlatform.system;
    inherit engineVersion;
  };

  packages = rec {
    unwrapped =
      (mkCustomFlutter {
        useNixpkgsEngine = false;
        version = flutterVersion;
        inherit engineVersion dart;
        engineSwiftShaderRev = "unused";
        engineSwiftShaderHash = "unused";
        patches = frameworkPatches ++ versionPatches;
        channel = "stable";
        src = flutterSource;
        inherit pubspecLock flutterTools;
        artifactHashes = { };
      }).overrideAttrs
        (oldAttrs: {
          # Nixpkgs stamps a synthetic revision. Keep the immutable SDK's
          # machine-readable identity aligned with our exact framework source;
          # plugin compilation checks it against SOURCE_LOCK.json.
          postBuild = (oldAttrs.postBuild or "") + ''
            jq --arg revision '${flutterRevision}' \
              '.frameworkRevision = $revision | .repositoryUrl = "https://github.com/denialwm/flutter.git"' \
              bin/cache/flutter.version.json > bin/cache/flutter.version.json.new
            mv bin/cache/flutter.version.json.new bin/cache/flutter.version.json
          '';
          passthru = oldAttrs.passthru // {
            engine = releaseEngine;
            inherit pinnedRawEngine;
            hostSourceEngine = sourceEngine;
            engineSource = applicationEngineSource;
            depotToolsSource = sourceEngine.depotToolsSource;
            inherit fetchedFlutter flutterSource;
            buildFlutterApplication =
              pkgs.callPackage (flutterNix + "/build-support/build-flutter-application.nix")
                {
                  flutter = packages.wrapped;
                  buildDartApplication = flutterBuildDartApplication;
                };
          };
        });

    # Denial builds Linux applications only, with the locked release engine.
    # buildFlutterApplication normally re-enables universal and target artifact
    # downloads through `override`; keep this wrapper on our supplied engine instead.
    wrapped = wrappedBase // {
      override = _: packages.wrapped;
      engine = releaseEngine;
      inherit pinnedRawEngine;
      hostSourceEngine = sourceEngine;
      engineSource = applicationEngineSource;
      depotToolsSource = sourceEngine.depotToolsSource;
      frameworkRevision = flutterRevision;
      inherit dart;
      inherit fetchedFlutter flutterSource;
    };
    # The host's wrapper can change its local-engine interface independently
    # of the pinned tool helper. Keep their definitions coupled while still
    # resolving every native dependency through the host package set.
    wrappedBase = pkgs.callPackage (flutterNix + "/wrapper.nix") {
      flutter = packages.unwrapped;
      supportedTargetFlutterPlatforms = [ ];
    };
  };
in
if maintenanceOnly then
  maintenanceSources
else
  assert lib.assertMsg (
    releaseEngineOverride == null || (releaseEngineOverride.sourceLockSha256 or null) == sourceLockHash
  ) "Engine artifacts do not match SOURCE_LOCK.json";
  assert lib.assertMsg (
    nixLock.schema_version == 1
  ) "unsupported nix/flutter-engine-lock.json schema";
  assert lib.assertMsg (nixLock.source_lock_sha256 == sourceLockHash) ''
    prebuilt/flutter-engine/SOURCE_LOCK.json changed without refreshing nix/flutter-engine-lock.json;
    run `tools/denial-nix refresh-engine-lock`
  '';
  assert lib.assertMsg (
    nixLock.flutter.revision == flutterRevision
  ) "Flutter revisions differ between the engine locks";
  assert lib.assertMsg (
    nixLock.skia.revision == sourceLock.skia.revision
  ) "Skia revisions differ between the engine locks";
  assert lib.assertMsg (
    nixLock.depot_tools.revision == sourceLock.depot_tools.revision
  ) "depot_tools revisions differ between the engine locks";
  assert lib.assertMsg (
    nixLock.engine.revision == engineVersion
  ) "Flutter engine revisions differ between the engine locks";
  assert lib.assertMsg (pubspecLock.flutter_revision == flutterRevision) ''
    Flutter changed without regenerating nix/flutter-pubspec-lock.json;
    run `tools/denial-nix refresh-pub-locks`
  '';
  packages.wrapped
