{
  lib,
  pkgs,
  runCommand,
  python3,
  denialFlutter,
  denial,
  expectedRawEngine,
  newerDriver ? null,
}:
let
  raw = denialFlutter.pinnedRawEngine;
  engine = denialFlutter.engine;
  probe = pkgs.callPackage ../engine-probe.nix {
    embedderHeader = "${raw}/out/host_release/flutter_embedder.h";
  };
  driver = "${pkgs.mesa}/lib/libgallium-${pkgs.mesa.version}.so";
in
assert lib.assertMsg (
  raw.drvPath == expectedRawEngine.drvPath
) "Host Nixpkgs changed the cached engine producer";
runCommand "denial-engine-cache-contract"
  {
    nativeBuildInputs = [
      python3
      pkgs.binutils
    ];
    exportReferencesGraph = [
      "runtime-closure"
      denial
    ];
  }
  ''
    python3 ${../engine-manifest.py} verify ${raw} \
      --source-lock ${denialSource}/prebuilt/flutter-engine/SOURCE_LOCK.json} \
      --nix-lock ${../flutter-engine-lock.json} --platform ${pkgs.stdenv.hostPlatform.system}
    ${probe}/bin/denial-engine-probe \
      ${engine}/out/host_release/libflutter_engine.so \
      ${denial.dartShell}/lib/libapp.so --driver ${driver} >engine-driver.log
    # The composed runtime must not retain another package set's libc.
    for path in $(sed -n '/^\/nix\/store\/.*-glibc-/p' runtime-closure); do
      case "$path" in
        ${pkgs.stdenv.cc.libc}|${lib.getBin pkgs.stdenv.cc.libc}) ;;
        *) echo "Unexpected runtime libc: $path" >&2; exit 1 ;;
      esac
    done
    ${lib.optionalString (newerDriver != null) ''
      # Model the reported failure with the stable loader and newer Mesa in
      # the same process. No graphics device or window is needed for dlopen.
      required_glibc="$(readelf --version-info ${newerDriver} \
        | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -n 1)"
      host_glibc=${lib.versions.majorMinor pkgs.stdenv.cc.libc.version}
      if [ -n "$required_glibc" ] \
        && [ "$required_glibc" != "$host_glibc" ] \
        && [ "$(printf '%s\n' "$host_glibc" "$required_glibc" | sort -V | tail -n 1)" = "$required_glibc" ]; then
        if ${probe}/bin/denial-engine-probe \
          ${engine}/out/host_release/libflutter_engine.so \
          ${denial.dartShell}/lib/libapp.so --driver ${newerDriver} \
          >mismatched-driver.log 2>&1; then
          echo "Expected the older libc to reject the newer driver" >&2
          exit 1
        fi
        grep -E 'GLIBC_[0-9.]+.*not found' mismatched-driver.log
      else
        echo "Newer driver does not require a newer libc; no mismatch to test" >mismatched-driver.log
      fi
    ''}
    mkdir -p $out
    cp engine-driver.log $out/
    ${lib.optionalString (newerDriver != null) "cp mismatched-driver.log $out/"}
  ''
