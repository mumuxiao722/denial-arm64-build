# denial-arm64-builder

[中文版](README_CN.md)

ARM64 patches for the `tools/denial-pc` build system of
[Denial](https://github.com/denialwm/denial), a Flutter-native Wayland
compositor; a GitHub Actions workflow that builds the patched source tree on an
ARM64 runner and packages the result for five distributions; and Nix packaging
ported from upstream.

Upstream `denial-pc` is configured to build for x86-64, so its build system does
not run natively on ARM64. Denial itself supports ARM64 source builds; what is
missing upstream is a native build path in that script and a release pipeline
that publishes ARM64 binaries. This repository supplies both.

The patch set was developed inside
[fedora-sheng](https://github.com/mumuxiao722/fedora-sheng), where it lived
under `.github/denial-arm64/`. It is now separate, so the patches can be used to
build or install ARM64 Denial on an ARM64 device running a supported
distribution, subject to the upstream host requirements, without being bound to
fedora-sheng.

## Status

Denial release: `v0.5.1`

Packages are published on the
[Releases page](https://github.com/mumuxiao722/denial-arm64-builder/releases).

## Installing

Each target provides three packages: `denial`, `denial-flutter-engine` and
`denial-plugin-manager`. `denial-plugin-manager` is optional and installs Denial
plugins.

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

## Local build

The Denial version built here is the tag or commit you check out. The build
commands are run from the root of the Denial checkout.

### Applying the patches

```sh
git clone --branch v0.5.1 https://github.com/denialwm/denial.git denial
cd denial
git apply /path/to/denial-arm64-builder/patches/denial-arm64.diff
python3 /path/to/denial-arm64-builder/patches/arm64-prep.py prep-checkout .
```

Keep this repository's `patches/` directory alongside the Denial checkout.
`arm64-prep.py prep-checkout` creates the ARM64 prebuilt metadata directories
that Denial checks against. The patched build system invokes the same file with
`patch-deps` during `gclient sync`, to rewrite the `DEPS` that sync fetches and
drop the openjdk dependency, which Flutter publishes only for linux-amd64.

### Host requirements

What it takes to compile Denial is written down upstream: see
[Host requirements](https://github.com/denialwm/denial/blob/v0.5.1/docs/BUILDING.md#host-requirements),
and `tools/denial-pc doctor` checks it. Per-distribution packaging tools are
documented under
[Debian, Fedora and openSUSE](https://github.com/denialwm/denial/blob/v0.5.1/docs/BUILDING.md#debian-fedora-and-opensuse-package-adapters)
and [Arch](https://github.com/denialwm/denial/blob/v0.5.1/docs/packaging/arch/README.md).

Two requirements are not mentioned in those documents.

`bsdtar` is required by all five targets, where upstream names it only in the
RPM packaging section. The deb target reaches it through
`verify-denial-native-package-metadata`, which requires it, and the APK target
through `package-denial-apk`. `tar` is not a substitute: an APK is several gzip
streams concatenated, and GNU tar stops after the first one, so it never reaches
the `.PKGINFO` or the signature behind it.

Denial cannot be compiled on Alpine, although it runs on musl-based systems
such as Alpine. The APKBUILD compiles only two small C libraries; the
compositor, the Flutter engine and the plugin manager are all built earlier, on
a glibc host, and `package-denial-apk` copies that staged payload into a
minimal Alpine root filesystem to assemble the `.apk`. The payload is linked
against glibc, so on Alpine's musl it requires `gcompat` at runtime.

### Build steps

```sh
./tools/denial-pc doctor      # report unmet host requirements
./tools/denial-pc bootstrap
./tools/denial-flutter-engine build
./tools/denial-pc build
```

## GitHub Actions build

The Denial version built by the workflow is the one named by `denial_ref`.

### Denial release

The workflow builds one Denial tag per run, named with `denial_ref`:

```sh
gh workflow run denial-arm64.yml -f denial_ref=v0.5.1
```

Every cache key derives from it, so a different version starts from a cold
engine cache. No other changes are required.

This field is for testing a new version on a test branch without disturbing the
tag `main` builds. Do not use it to change which version is the default:

```sh
gh workflow run denial-arm64.yml --ref bump-denial-<tag> -f denial_ref=<tag>
```

### Artifacts and releases

Fork this repository and run `Build Denial (ARM64)` from the Actions tab. The
workflow builds on an ARM64 runner and uploads packages as workflow artifacts,
kept for seven days by default; set `publish_release` to attach them to a
GitHub release instead. These artifacts are build outputs, not a package
repository.

## Nix

`nix/` is a copy of upstream's Nix packaging, committed here rather than
imported from the flake input. The flake pins Denial `v0.5.1` and a `plugins`
input. Upstream's copy builds on `x86_64-linux` only and carries no AArch64
engine hash; `nix/flutter-engine-lock.json` carries both hashes an AArch64
build requires, one for the Dart SDK and one for the engine source closure.

| Output | Contents |
|---|---|
| `nixosModules.default` | The NixOS module, `programs.denial.enable` |
| `overlays.default` | `denial`, `denialPluginManager`, and the engine |
| `packages.<system>.trial-rootfs` | A minimal NixOS system, built to test the install |

Two workflows are provided:

| Workflow | Job |
|---|---|
| Nix Flake Check | **Evaluate the flake on AArch64** |
|  | **Resolve the AArch64 engine hashes** — only when `refresh_engine_hashes` is set. Blanks the two hashes and resolves them again, reporting what Nix prints as `got:`. |
| Nix Install Check | **Install a system to test whether Denial can be installed** |

### On NixOS

Declare the flake input and import `nixosModules.default` in a NixOS
configuration:

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
            programs.denial = {
              enable = true;
              plugins.enable = true; # optional
            };
          }
        ];
      };
    };
}
```

Add the binary cache:

```nix
{
  nix.settings.substituters = [ "https://denial-arm64.cachix.org" ];
  nix.settings.trusted-public-keys = [
    "denial-arm64.cachix.org-1:FMxOqIH4Q1UX/sxmZxspx73o68MLKSd48ajvBjYIA0A="
  ];
}
```

Leave `denial.cachix.org` out: it is not an AArch64 cache, and a substituter
that can only miss costs a lookup on every path.

### On non-NixOS with the Nix package manager

Declare the flake input in the Nix configuration. The overlay provides
`denial`, and `denialPluginManager` for Denial's plugin tooling:

```nix
{
  inputs.denial.url = "github:mumuxiao722/denial-arm64-builder";

  outputs =
    { nixpkgs, denial, ... }:
    {
      nixConfigurations.my-host = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          {
            nixpkgs.overlays = [ denial.overlays.default ];
              environment.systemPackages = [
                pkgs.denial
                pkgs.denialPluginManager # optional
              ];
          }
        ];
      };
    };
}
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).