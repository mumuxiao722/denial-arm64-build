# denial-arm64-builder

[中文版](README_CN.md)

ARM64 patches for the `tools/denial-pc` build system of
[Denial](https://github.com/denialwm/denial), a Flutter-native Wayland
compositor, plus a GitHub Actions workflow that builds the patched tree on an
ARM64 runner and packages the result for five distributions.

Upstream `denial-pc` is configured to build for x86-64, so its build system does
not run natively on aarch64. Denial itself supports aarch64 source builds; what
is missing upstream is a native build path in that script and a release
pipeline that publishes ARM64 binaries. This repository supplies aarch64
support for the build system and its packaging adapters, and a
workflow that turns a Denial tag into RPM, deb, APK and Arch packages.

The patch set was developed inside
[fedora-sheng](https://github.com/mumuxiao722/fedora-sheng), where it lived
under `.github/denial-arm64/`. It is now separate, so a distribution can adopt
the ARM64 patches without taking on the rest of that image builder.

## Supported Denial versions

The workflow tracks one Denial tag at a time. The tracked ref is the repository
variable `DENIAL_REF`:

```sh
gh variable set DENIAL_REF --body v0.5.0
```

Every cache key derives from it, so moving to another release invalidates the
engine cache on its own. Nothing else needs editing.

## Using the patches

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
cd denial
git apply /path/to/denial-arm64-builder/patches/denial-arm64.diff
python3 /path/to/denial-arm64-builder/patches/arm64-prep.py prep-checkout .
```

Keep this repository's `patches/` directory alongside the Denial checkout.
`arm64-prep.py prep-checkout` creates the ARM64 prebuilt metadata directories
Denial checks against, and retargets the Alpine minirootfs to aarch64; the
patched build system calls the same file with `patch-deps` to rewrite the
`DEPS` that `gclient sync` fetches.

The diff carries the whole change set against `v0.5.0`, so what it does is
readable with `git diff` afterwards.

## Host tools

What it takes to compile Denial is written down upstream: see
[Host requirements](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#host-requirements),
and `tools/denial-pc doctor` checks it for you. Per-distribution packaging
tools are documented under
[Debian, Fedora and openSUSE](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#debian-fedora-and-opensuse-package-adapters)
and [Arch](https://github.com/denialwm/denial/blob/v0.5.0/docs/packaging/arch/README.md).

Two things those documents do not say:

`bsdtar` is needed by all five targets, where upstream names it only for RPM
output. The deb target reaches it through `verify-denial-native-package-metadata`,
which requires it, and the APK target through `package-denial-apk`. `tar`
cannot replace it: an APK is several gzip streams concatenated, and GNU tar
stops after the first one, so it never reaches the `.PKGINFO` or the signature
behind it.

Denial cannot be compiled on Alpine, even though it runs on musl-based
systems such as Alpine. The APKBUILD compiles only two small C libraries;
the compositor, the Flutter engine and the plugin manager are all built
earlier, on a glibc host, and `package-denial-apk` copies that staged payload
into a minimal Alpine root filesystem to assemble the `.apk`. The payload is
linked against glibc, so on Alpine's musl it needs `gcompat` at runtime.

## Building

Fork this repository and run the workflow from the Actions tab. It builds on an
ARM64 runner and uploads the packages as workflow artifacts, which are kept for
seven days; check `publish_release` to attach them to a GitHub release instead.
These artifacts are build output, not a software repository.

## Installing

The compositor and the Flutter engine are released as separate packages, but
they are not independent: the compositor depends on the engine in every
distribution below, so installing it pulls the engine in. Install both and let
the package manager resolve it.

| Distribution | Compositor | Engine | Plugin manager |
|---|---|---|---|
| Debian / Ubuntu | `denial` | `denial-flutter-engine` | `denial-plugin-manager`, optional |
| Fedora / openSUSE | `denial` | `denial-flutter-engine` | `denial-plugin-manager`, optional |
| Arch | `denial` | `denial-flutter-engine` | `denial-plugin-manager`, optional |
| Alpine | `denial` | `denial-flutter-engine` | `denial-plugin-manager`, optional |

According to upstream, `denial-plugin-manager` is an optional package for
installing Denial plugins.

```sh
# Arch. The engine filename uses + where makepkg puts the epoch's colon,
# because artifacts cannot contain one. pacman reads the version from inside
# the package, so the name does not matter.
sudo pacman -U denial-flutter-engine-*.pkg.tar.gz denial-*.pkg.tar.gz
sudo pacman -U denial-plugin-manager-*.pkg.tar.gz                  # optional

# Fedora
sudo dnf install ./denial-flutter-engine-*.rpm ./denial-*.rpm
sudo dnf install ./denial-plugin-manager-*.rpm                    # optional

# openSUSE
sudo zypper install ./denial-flutter-engine-*.rpm ./denial-*.rpm
sudo zypper install ./denial-plugin-manager-*.rpm                 # optional

# Debian / Ubuntu
sudo apt install ./denial-flutter-engine-*.deb ./denial-*.deb
sudo apt install ./denial-plugin-manager-*.deb                    # optional

# Alpine
sudo apk add --allow-untrusted ./*.apk
sudo apk add --allow-untrusted ./denial-plugin-manager-*.apk     # optional
```

Installing writes `/usr/share/wayland-sessions/denial.desktop`, so Denial
appears in the session selector of the display manager you already use.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).