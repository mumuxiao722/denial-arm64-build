# denial-arm64-builder

[中文版](README_CN.md)

Builds [Denial](https://github.com/denialwm/denial), a Flutter-native Wayland
compositor, for ARM64 and packages it for five distributions.

Upstream's `tools/denial-pc` build system targets x86-64 and does not support
ARM64. This repository patches it for aarch64 with a source-built Flutter
engine, runs the build on an ARM64 CI runner, and uploads the RPM, deb, APK
and Arch packages that come out.

The patch set was developed inside
[fedora-sheng](https://github.com/mumuxiao722/fedora-sheng), where it lived
under `.github/denial-arm64/`. It now lives here so that any distribution can
consume the same patches without adopting the rest of that image builder.

## Supported Denial versions

This repository tracks one tag at a time. The tracked ref is the repository
variable `DENIAL_REF`:

```sh
gh variable set DENIAL_REF --body v0.5.0
```

| Denial tag | Patch set |
| --- | --- |
| `v0.5.0` | current |

Every cache key derives from that variable, so moving to a new release
invalidates the engine cache automatically.

## Usage

Check out the Denial tag you want to build and apply the patches:

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/denial-arm64-builder.sh denial
```

The patch set is anchored to the shapes that the tracked tag ships. The script
is idempotent: running it again reports each target as already patched. If a
future upstream release reshapes any anchored code the script exits naming the
anchor it could not find, rather than applying a partial change.

## What the patches cover

Build system:

- `tools/denial-flutter-engine` — aarch64 GN arguments, ARM64 build paths,
  DEPS hook for the engine checkout
- `tools/denial-pc` — aarch64 arch paths, lenient engine checksum handling
  for a self-built engine
- `tools/stage-denial-runtime` — host-CPU aware bundle and engine paths,
  lenient engine SHA-256
- `tools/prepare-denial-plugin-kit` — lenient engine checksum
- `patches/patch-deps.py` — applied during `gclient sync`

Packaging:

- `packaging/fedora/denial.spec` — `ExclusiveArch` includes aarch64
- `packaging/opensuse/denial.spec` — `ExclusiveArch` includes aarch64
- `tools/package-denial-rpm` — widened RPM globs
- `tools/package-denial-deb` — Debian architecture derived from `uname -m`
  instead of a literal `amd64`, in both the control fields and the output
  filenames
- `tools/package-denial-arch` — engine checksum read from the host-arch
  directory rather than `linux-x64-release`
- `packaging/arch/**/PKGBUILD` — `arch=('x86_64' 'aarch64')`
- `tools/verify-denial-native-package-metadata` — accepts an aarch64 RPM arch

## ARM64 placeholder metadata

The seed step creates `prebuilt/flutter-engine/linux-arm64-{debug,profile,
release}/` with empty `args.gn`, `libflutter_engine.so.sha256`,
`ENGINE_REVISION` and `FLUTTER_REVISION`, copying only the license and build
documentation from the x86-64 directory. Denial's own checks compare against
these files; the patches make an empty baseline skip the comparison instead of
failing.

## Building

The workflow runs on `ubuntu-24.04-arm` and is dispatched manually, or on a
push touching `patches/`. It takes `publish_release` (default off) as its only
input; everything else derives from `DENIAL_REF`.

One cache is maintained:

- `denial-engine-cache-<ref>` — the finished `libflutter_engine.so` and the
  build state that goes with it, saved right after `denial-flutter-engine
  build`.

Only the engine's finished artifacts are cached. Its Skia objects run to tens
of gigabytes, past the repository's 10 GB cache quota, so they are rebuilt on
every run, as are the Rust binaries and the Flutter bundle. A run therefore
spends roughly 40 minutes in the engine and another 50 in `denial-pc build`
before it reaches packaging. The cache saves the final link and packaging
step, not the bulk compile.

Packaging targets, all from the same staged payload. Fedora and openSUSE
produce the same RPM filenames, so they are kept apart by directory when
packaging and by artifact name when uploading:

| Command | Uploaded as | Matched by |
| --- | --- | --- |
| `denial-pc fedora-package` | `denial-rpm-fedora-arm64` | `packages/denial-[0-9]*.rpm` |
| `denial-pc opensuse-package` | `denial-rpm-opensuse-arm64` | `packages/opensuse/denial-[0-9]*.rpm` |
| `denial-pc debian-package` | `denial-deb-arm64` | `packages/*.deb` |
| `denial-pc alpine-package` | `denial-apk-arm64` | `packages/*.apk` |
| `denial-pc arch-package` | `denial-arch-arm64` | `packages/*.pkg.tar.zst` |

The RPM and deb patterns catch only the compositor; the Flutter engine ships as
its own package. Each RPM target therefore uploads a second artifact:

| Artifact | Matched by |
| --- | --- |
| `denial-flutter-engine-rpm-fedora-arm64` | `packages/denial-flutter-engine-*.rpm` |
| `denial-flutter-engine-rpm-opensuse-arm64` | `packages/opensuse/denial-flutter-engine-*.rpm` |

## Consumers

`mumuxiao722/fedora-sheng` carries a copy of this patch set under
`.github/denial-arm64/` and applies it in its `build-denial` job to produce
installable RPMs for the Xiaomi Pad 6S Pro image.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).