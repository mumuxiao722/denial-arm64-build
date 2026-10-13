# Host-independent, source-built engine and compiler assets for the binary cache.
{
  lib,
  denialSource,
  pkgs,
  runCommand,
  python3,
  patchelf,
  removeReferencesTo,
  flutterNixpkgs ? pkgs.path,
}:
let
  sourceEngine = pkgs.callPackage ./flutter-engine-source.nix { inherit flutterNixpkgs; };
  minimumGlibc = lib.versions.majorMinor pkgs.stdenv.cc.libc.version;
  minimumCompilerRuntime = lib.versions.majorMinor pkgs.stdenv.cc.cc.version;
  sourceLockSha256 = builtins.hashFile "sha256" ${denialSource}/prebuilt/flutter-engine/SOURCE_LOCK.json;
in
runCommand "denial-flutter-engine-raw-${sourceEngine.version}"
  {
    nativeBuildInputs = [
      python3
      patchelf
      removeReferencesTo
    ];
    exportReferencesGraph = [
      "producer-closure"
      sourceEngine.release
    ];
    # Raw artifacts are self-contained and must retain no producer closure.
    allowedReferences = [ ];
    passthru = {
      inherit
        minimumGlibc
        minimumCompilerRuntime
        sourceLockSha256
        sourceEngine
        ;
      producerNixpkgsVersion = lib.version;
    };
    meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
  }
  ''
    mkdir -p $out/out/host_release $out/licenses
    for asset in \
      libflutter_engine.so icudtl.dat gen_snapshot impellerc font-subset \
      dart-sdk flutter_patched_sdk gen/dart-pkg/sky_engine shader_lib flutter_linux \
      gen/const_finder.dart.snapshot libflutter_linux_gtk.so; do
      mkdir -p "$out/out/host_release/$(dirname "$asset")"
      cp -RL ${sourceEngine}/out/host_release/"$asset" "$out/out/host_release/$asset"
    done
    cp ${sourceEngine.src}/src/flutter/shell/platform/embedder/embedder.h \
      $out/out/host_release/flutter_embedder.h
    cp ${denialSource}/prebuilt/flutter-engine/linux-x64-release/LICENSE.flutter} $out/licenses/LICENSE.flutter
    cp ${denialSource}/prebuilt/flutter-engine/linux-x64-release/LICENSE.third_party} $out/licenses/LICENSE.third_party
    chmod -R u+w $out
    # Neutralize the producer's loader/search paths on copies. These binaries
    # are build inputs, and must be adapted before execution on a NixOS host.
    mapfile -t producerReferences < <(sed -n '/^\/nix\/store\//p' producer-closure)
    while IFS= read -r -d "" file; do
      if patchelf --print-rpath "$file" >/dev/null 2>&1; then
        if patchelf --print-needed "$file" | grep -qF /nix/store/; then
          echo "Unexpected absolute ELF dependency: $file" >&2
          exit 1
        fi
        patchelf --remove-rpath "$file"
        if patchelf --print-interpreter "$file" >/dev/null 2>&1; then
          patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$file"
        fi
        # Patchelf can leave obsolete path strings in the ELF string table.
        # Scrub those references after removing their loader/search entries.
        for reference in "''${producerReferences[@]}"; do
          if LC_ALL=C grep -qaF "$reference" "$file"; then
            remove-references-to -t "$reference" "$file"
          fi
        done
      fi
    done < <(find $out -type f -print0)
    python3 ${./engine-manifest.py} create "$out" \
      --source-lock ${denialSource}/prebuilt/flutter-engine/SOURCE_LOCK.json} \
      --nix-lock ${./flutter-engine-lock.json} \
      --configuration ${sourceEngine.release}/denial-args.gn \
      --platform x86_64-linux --minimum-glibc ${minimumGlibc} \
      --minimum-compiler-runtime ${minimumCompilerRuntime} \
      --nixpkgs-version ${lib.escapeShellArg lib.version}
  ''
