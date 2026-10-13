# Portable engine experiment

This retains the original lab experiment, not a supported package selection or
public cache contract. Normal packages now use the source-built pinned producer
and verified host adapter in `nix/flutter-engine-{raw,adapt}.nix`.
The internal `releaseEngineOverride` argument lets a test overlay reuse verified
release engine/compiler outputs while building the compositor and Dart apps
with the host's Nixpkgs.

`portable-engine.nix` copies raw artifacts, verifies the engine checksum, removes
old ELF search paths on those copies, and runs the host's `autoPatchelfHook`.
The immutable raw artifact has the same store identity across host package sets;
the adapted output has a different identity for each host. No loader shim is
needed. The raw artifact's minimum glibc requirement still matters: adapting ELF
paths cannot make a binary run against an older, unsupported libc.

## Inputs and example

Use artifacts from a release build verified against the repository's exact
`prebuilt/flutter-engine/SOURCE_LOCK.json`. `engineRoot` must contain
`out/host_release/`, including the engine, ICU data, snapshots and tools used by
the Flutter application builder (`gen_snapshot`, `impellerc`, `font-subset`,
`flutter_patched_sdk`, `gen/dart-pkg/sky_engine`, `shader_lib`, Flutter Linux
headers/library and `gen/const_finder.dart.snapshot`). The Dart SDK is supplied
separately from the lock-matched maintenance package. Keep a matching release
shell bundle for the probe.

For example, a local `experiment.nix` next to a Denial checkout named `source`
and verified artifacts below `inputs`:

```nix
let
  denial = builtins.getFlake "path:${toString ./source}";
  host = builtins.getFlake "github:NixOS/nixpkgs/<exact-host-revision>";
  base = import host { system = "x86_64-linux"; };
  maintenance = base.callPackage ./source/nix/flutter-engine.nix {
    flutterNixpkgs = denial.inputs.nixpkgs;
    maintenanceOnly = true;
  };
  experiment = import ./source/nix/experiments/portable-engine.nix {
    pkgs = base;
    engineRoot = ./inputs/engine;
    bundle = ./inputs/bundle;
    embedderHeader = ./inputs/engine/out/host_release/flutter_embedder.h;
    expectedEngineSha256 = "<verified engine SHA-256>";
    dartSdk = maintenance.dart;
  };
  pkgs = import host {
    system = "x86_64-linux";
    overlays = [
      denial.overlays.default
      (final: _: {
        denialFlutter = final.callPackage ./source/nix/flutter-engine.nix {
          flutterNixpkgs = denial.inputs.nixpkgs;
          releaseEngineOverride = experiment.engine;
        };
      })
    ];
  };
in {
  inherit (experiment) engine runtime probe identity;
  package = pkgs.denial;
}
```

Build the probe and runtime, then run against a render node as a user with
access to it. This creates no window or scanout:

```sh
nix build --impure --file experiment.nix probe --out-link probe
nix build --impure --file experiment.nix runtime --out-link runtime
./probe/bin/denial-portable-engine-probe \
  ./runtime/lib/libflutter_engine.so ./runtime/lib/libapp.so /dev/dri/renderD128
nix build --impure --file experiment.nix package --out-link package
./package/bin/denial-session --check
```

The probe checks the Denial extension symbols, Flutter procedure table, release
AOT data loading, GBM driver loading, and surfaceless EGL/GLES initialization.
It does not initialize Flutter or execute Dart. A full Denial session on each
actual host graphics stack is therefore required too. Record the process's
mapped engine, AOT library, libc and Mesa driver and the session service health.
Visual validation remains user-owned.

## Cache and production boundary

The lab uses `nix copy` to round-trip the raw store path through an isolated file
binary cache. This proves reuse of the same bytes; it does not publish to Cachix
or establish a production artifact supply chain.

The normal producer binds a complete manifest to the locked sources and recorded
build configuration and relies on Nix's exact derivation/cache signature contract.
It has a source-build fallback and host compatibility checks. This retained
experiment validates the engine
checksum and rejects an override stamped with a different source-lock hash;
that stamp is supplied by the test harness, not independently authenticated
producer provenance. Only x86_64 release mode is covered here.

See [the validation record](../../packaging/nixos/VALIDATION.md) for the tested
systems, results and limitations.
