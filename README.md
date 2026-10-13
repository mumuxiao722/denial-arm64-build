# denial-arm64-builder

[中文版](README_CN.md)

ARM64 patches for the `tools/denial-pc` build system of
[Denial](https://github.com/denialwm/denial), a Flutter-native Wayland
compositor, plus a GitHub Actions workflow that builds the patched tree on an
ARM64 runner and packages the result for five distributions.

Upstream `denial-pc` is configured to build for x86-64, so its build system does
not run natively on ARM64. Denial itself supports ARM64 source builds; what
is missing upstream is a native build path in that script and a release
pipeline that publishes ARM64 binaries. This repository supplies ARM64
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
Denial checks against, and retargets the Alpine minirootfs to ARM64; the
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

## Nix

There is a flake that pins the same Denial release and imports upstream's own
Nix packaging, ported to AArch64. Upstream pins that packaging to x86_64-linux
and carries no AArch64 engine hash, so the port had to add one for the Dart SDK
and one for the engine source closure; both are in
`nix/flutter-engine-lock.json`.

| Output | What it is |
|---|---|
| `nixosModules.denial` | The NixOS module, `programs.denial.enable` |
| `overlays.default` | `denial`, `denialPluginManager`, and the engine |
| `packages.<system>.trial-rootfs` | A minimal system, built only to be looked at |

AArch64 has no engine on denial.cachix.org, so building takes hours.

Two workflows, both `workflow_dispatch`:

| Workflow | Job |
|---|---|
| Nix Flake Check | **Evaluate the flake on AArch64** — seconds |
| | **Resolve the AArch64 engine hashes** — only when `refresh_engine_hashes` is set. Blanks the two hashes and resolves them again, reporting what Nix prints as `got:`. |
| Nix System Check | **Build a minimal NixOS system and check what it contains** — hours |

## Installing

Every target ships the same three packages under the same names: `denial`,
`denial-flutter-engine` and `denial-plugin-manager`. According to upstream,
`denial-plugin-manager` is optional and installs Denial plugins.

```sh
# Debian / Ubuntu
sudo apt install ./denial-flutter-engine_*.deb ./denial_[0-9]*_*.deb
sudo apt install ./denial-plugin-manager_*.deb                    # optional

# Arch
sudo pacman -U denial-flutter-engine-*.pkg.tar.gz denial-[0-9]*.pkg.tar.gz
sudo pacman -U denial-plugin-manager-*.pkg.tar.gz                  # optional

# Fedora
sudo dnf install ./denial-flutter-engine-*.rpm ./denial-[0-9]*.rpm
sudo dnf install ./denial-plugin-manager-*.rpm                    # optional

# openSUSE
sudo zypper install ./denial-flutter-engine-*.rpm ./denial-[0-9]*.rpm
sudo zypper install ./denial-plugin-manager-*.rpm                 # optional

# Alpine
sudo apk add --allow-untrusted ./denial-flutter-engine-*.apk ./denial-[0-9]*.apk
sudo apk add --allow-untrusted ./denial-plugin-manager-*.apk     # optional
```

### With Nix

The flake carries a NixOS module and an overlay:

```nix
{
  inputs.denial.url = "github:mumuxiao722/denial-arm64-builder";

  outputs =
    { nixpkgs, denial, ... }:
    {
      nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          denial.nixosModules.default
          {
            programs.denial.enable = true;
            programs.denial.plugins.enable = true; # The plugin manager.
          }
        ];
      };
    };
}
```

Rebuild the system, then choose **Denial** in the display manager you already
use; the module does not enable one. `programs.denial.package` replaces the
package without replacing the module.

Outside NixOS the overlay is enough:

```nix
nixpkgs.overlays = [ inputs.denial.overlays.default ];
environment.systemPackages = [
  pkgs.denial
  pkgs.denialPluginManager
];
```

The engine is not on `denial.cachix.org` on AArch64: that cache carries
upstream's x86_64 output, and a different architecture is a different store
path, so nothing in it is ever hit and there is nothing to configure. What that
costs is that the engine is compiled from source the first time, which takes
hours.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).