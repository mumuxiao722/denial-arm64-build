# denial-arm64-builder

[中文版](README_CN.md)

ARM64 patches for the `tools/denial-pc` build system of
[Denial](https://github.com/denialwm/denial), a Flutter-native Wayland
compositor, plus a GitHub Actions workflow that builds the patched tree on an
ARM64 runner and packages the result for five distributions.

Upstream `denial-pc` targets x86-64 and has no ARM64 support. This repository
supplies aarch64 support for the build system and its packaging adapters, and a
workflow that turns a Denial tag into RPM, deb, APK and Arch packages.

The patch set was developed inside
[fedora-sheng](https://github.com/mumuxiao722/fedora-sheng), where it lived
under `.github/denial-arm64/`. It is now separate, so a distribution can adopt
the ARM64 patches without taking on the rest of that image builder.

## Supported Denial versions

The workflow tracks one Denial tag at a time. The tracked ref is the repository
variable `DENIAL_REF`:

```sh
gh variable set DENIAL_REF --body v0.6.0
```

Every cache key derives from it, so moving to another release invalidates the
engine cache on its own. Nothing else needs editing.

## Using the patches

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/denial-arm64-builder.sh denial
```

The script anchors on the code shapes the tracked tag ships and is idempotent:
running it twice reports each target as already patched. If a future release
reshapes an anchored block, the script exits naming the anchor it could not
find instead of applying a partial change.

## Building

Fork this repository and run the workflow from the Actions tab. It builds on an
ARM64 runner and uploads the packages as workflow artifacts; check
`publish_release` to attach them to a GitHub release instead.

The compositor and the Flutter engine ship as separate packages, so installing
the compositor does not pull the engine in by accident.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).