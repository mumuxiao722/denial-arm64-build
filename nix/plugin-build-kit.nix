{
  lib,
  runCommand,
  python3,
  gitMinimal,
  coreutils,
  denialFlutter,
  src,
  sourceRevision,
  stdenv,
}:

let
  targetPlatform =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "Denial does not support ${stdenv.hostPlatform.system}");
  release = "source/prebuilt/flutter-engine/${targetPlatform}-release";
  # Upstream ships only the x86_64 release directory. The licences are text and
  # do not vary by architecture, so AArch64 gets a copy of them under its own
  # name; the engine checksum is this host's engine either way.
  upstreamRelease = "source/prebuilt/flutter-engine/linux-x64-release";
in

# Package existing Nix engine/compiler outputs. Enabling a plugin never invokes
# Nix or builds an engine; the manager provisions this kit into user-owned state.
runCommand "denial-plugin-build-kit"
  { nativeBuildInputs = [ python3 gitMinimal coreutils ]; }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cp -R ${src} source
    chmod -R u+w source
    # On x86_64 the directory already exists and copying onto itself fails, so
    # this only runs where upstream has nothing to copy from.
    if [ "$release" != "$upstreamRelease" ]; then
      mkdir -p "$release"
      cp "$upstreamRelease"/LICENSE.flutter "$release"/LICENSE.flutter
      cp "$upstreamRelease"/LICENSE.third_party "$release"/LICENSE.third_party
    fi
    # The Nix engine has store-linked dependencies and therefore its own bytes.
    # Record the exact same engine that nix/dart-shell.nix installs, rather than
    # claiming it has the checksum of the separately packaged native build.
    sha256sum ${denialFlutter.engine}/out/host_release/libflutter_engine.so \
      > "$release"/libflutter_engine.so.sha256
    python3 source/tools/prepare-denial-plugin-kit \
      --source-root source \
      --source-revision ${lib.escapeShellArg sourceRevision} \
      --flutter-root ${denialFlutter.sdk} \
      --flutter-revision ${lib.escapeShellArg denialFlutter.frameworkRevision} \
      --engine-root ${denialFlutter.engine} \
      --engine-source-root ${denialFlutter.engineSource} \
      --engine-target host_release --platform ${targetPlatform} --output "$out"
    test -f "$out/flutter/bin/cache/flutter_tools.snapshot"
    test -f "$out/runtime/.denial-ui-source.json"
  ''
