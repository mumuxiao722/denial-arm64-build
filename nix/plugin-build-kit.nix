{
  lib,
  runCommand,
  python3,
  gitMinimal,
  coreutils,
  denialFlutter,
  src,
  sourceRevision,
}:

# Package existing Nix engine/compiler outputs. Enabling a plugin never invokes
# Nix or builds an engine; the manager provisions this kit into user-owned state.
runCommand "denial-plugin-build-kit"
  { nativeBuildInputs = [ python3 gitMinimal coreutils ]; }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cp -R ${src} source
    chmod -R u+w source
    # The Nix engine has store-linked dependencies and therefore its own bytes.
    # Record the exact same engine that nix/dart-shell.nix installs, rather than
    # claiming it has the checksum of the separately packaged native build.
    sha256sum ${denialFlutter.engine}/out/host_release/libflutter_engine.so \
      > source/prebuilt/flutter-engine/linux-x64-release/libflutter_engine.so.sha256
    python3 source/tools/prepare-denial-plugin-kit \
      --source-root source \
      --source-revision ${lib.escapeShellArg sourceRevision} \
      --flutter-root ${denialFlutter.sdk} \
      --flutter-revision ${lib.escapeShellArg denialFlutter.frameworkRevision} \
      --engine-root ${denialFlutter.engine} \
      --engine-source-root ${denialFlutter.engineSource} \
      --engine-target host_release --platform linux-x64 --output "$out"
    test -f "$out/flutter/bin/cache/flutter_tools.snapshot"
    test -f "$out/runtime/.denial-ui-source.json"
  ''
