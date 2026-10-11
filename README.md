# denial-arm64-build

[中文版](README_CN.md)

ARM64 build support for [Denial](https://github.com/denialwm/denial), a
Flutter-native Wayland compositor.

Upstream's `tools/denial-pc` build system targets x86-64 and does not support
ARM64. This repository carries the patches that make Denial build on aarch64
with a source-built Flutter engine, so the result can be installed on ARM64
hardware.

These patches were developed inside
[fedora-sheng](https://github.com/mumuxiao722/fedora-sheng), where they lived
under `.github/denial-arm64/`. They now live here so that any distribution can
consume the same patch set without adopting the rest of that image builder.

## Supported Denial versions

| Denial tag | Patch set |
| --- | --- |
| `v0.5.0` | current |

## Usage

Check out the Denial tag you want to build and apply the patches:

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/patch-denial-arm64.sh denial
```

The script is idempotent: running it again reports each target as already
patched. Every substitution is anchored, so if an upstream refactor moves the
patched code the script exits with the name of the anchor it could not find
rather than applying a partial change.

## What the patches cover

- `tools/denial-flutter-engine` — aarch64 GN arguments, ARM64 build paths,
  DEPS hook for the engine checkout
- `tools/denial-pc` — aarch64 arch paths, lenient engine checksum handling
  for a self-built engine
- `tools/stage-denial-runtime` — host-CPU aware bundle and engine paths,
  lenient engine SHA-256
- `tools/prepare-denial-plugin-kit` — lenient engine checksum
- `tools/package-denial-rpm` — widened RPM globs
- `packaging/fedora/denial.spec` — `ExclusiveArch` includes aarch64
- `tools/verify-denial-native-package-metadata` — accepts an aarch64 RPM arch

`patches/patch-deps.py` is applied by the engine patch during `gclient sync`.

## ARM64 placeholder metadata

The seed step creates `prebuilt/flutter-engine/linux-arm64-{debug,profile,
release}/` with empty `args.gn`, `libflutter_engine.so.sha256`,
`ENGINE_REVISION` and `FLUTTER_REVISION`, copying only the license and build
documentation from the x86-64 directory. Denial's own checks compare against
these files; the patches make an empty baseline skip the comparison instead of
failing.

## Consumers

`mumuxiao722/fedora-sheng` applies this patch set in its `build-denial` job and
produces installable RPMs. It checks out this repository and runs
`patches/patch-denial-arm64.sh` against its Denial checkout rather than
carrying its own copy.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).