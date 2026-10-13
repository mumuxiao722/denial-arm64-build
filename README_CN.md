# denial-arm64-builder

[English](README.md)

[Denial](https://github.com/denialwm/denial) 是一个基于 Flutter 的 Wayland
合成器。本仓库提供其 `tools/denial-pc` 构建系统的 ARM64 补丁，以及一个
GitHub Actions 工作流——在 ARM64 runner 上构建打过补丁的源码树，并把结果打包给
五个发行版。

上游 `denial-pc` 按 x86-64 配置，它的构建系统无法在 ARM64 上原生运行。Denial 本身是
支持 ARM64 源码构建的；上游缺的是那个脚本里的原生构建路径，以及发布 ARM64 二进制的
流水线。本仓库为该构建系统及其打包适配器补充 ARM64 支持，并提供一个把 Denial tag
转换为 RPM、deb、APK 和 Arch 安装包的工作流。

这套补丁最初在 [fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) 中开发，
位于 `.github/denial-arm64/` 目录下。现在独立出来，发行版可以只采用 ARM64 补丁，
而不必连带那个镜像构建项目的其余部分。

## 支持的 Denial 版本

工作流只追踪一个 Denial tag。被追踪的 ref 是仓库变量 `DENIAL_REF`：

```sh
gh variable set DENIAL_REF --body v0.5.0
```

所有缓存键都由它派生，所以换到新版本会让引擎缓存自动失效。其他地方都不需要改动。

## 使用补丁

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
cd denial
git apply /path/to/denial-arm64-builder/patches/denial-arm64.diff
python3 /path/to/denial-arm64-builder/patches/arm64-prep.py prep-checkout .
```

请把本仓库的 `patches/` 目录放在 Denial 检出目录旁边。`arm64-prep.py
prep-checkout` 用来创建 Denial 校验所需的 ARM64 prebuilt 元数据目录，并把 Alpine
minirootfs 换成 ARM64；打过补丁的构建系统会用同一个文件、传入 `patch-deps`
参数，去改写 `gclient sync` 拉取的 `DEPS`。

这个 diff 包含针对 `v0.5.0` 的全部改动，所以打完之后用 `git diff` 就能看清它做了什么。

## 宿主工具

编译 Denial 需要哪些工具，见上游文档的
[Host requirements](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#host-requirements)
一节；`tools/denial-pc doctor` 可以直接检查。各发行版的打包工具分别写在
[Debian、Fedora 与 openSUSE](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#debian-fedora-and-opensuse-package-adapters)
和 [Arch](https://github.com/denialwm/denial/blob/v0.5.0/docs/packaging/arch/README.md) 文档里。

那两份文档没说的有两件事。

`bsdtar` 五个目标都要，而上游只在 RPM 那句里提到它。deb 目标经
`verify-denial-native-package-metadata` 用到它、那个脚本会检查它，APK 目标经
`package-denial-apk` 用到它。`tar` 替代不了：一个 APK 是好几段 gzip 流拼起来的，
而 GNU tar 读到第一段就停，看不到后面流里的 `.PKGINFO` 和签名。

Denial 无法在 Alpine 上编译，尽管它能在 Alpine 这样的 musl 发行版上运行。
APKBUILD 里只编译两个很小的 C 库；合成器、Flutter 引擎和插件管理器都是在
glibc 宿主上先行构建好的，`package-denial-apk` 把这份已 stage 的产物复制进一个
精简的 Alpine 根文件系统，再组装成 `.apk`。产物链接的是 glibc，所以在 Alpine 的
musl 上运行需要 `gcompat`。

## 构建

Fork 本仓库，在 Actions 页面运行工作流。它在 ARM64 runner 上构建，并把安装包作为工作流
产物上传，保留七天；勾选 `publish_release` 则改为附到一个 GitHub release 上。
这些产物是构建输出，不构成软件源。

## Nix

仓库里有一个 flake，钉住同一个 Denial 版本，使用上游自己的 Nix 打包，移植到了 ARM64。上游
把那份打包钉死在 x86_64-linux，而且没有 ARM64 的引擎哈希，所以移植必须补上一个 Dart SDK
的和一个引擎源码闭包的；两个值都在 `nix/flutter-engine-lock.json` 里。

| 输出 | 是什么 |
|---|---|
| `nixosModules.denial` | NixOS 模块，`programs.denial.enable` |
| `overlays.default` | `denial`、`denialPluginManager`，以及引擎 |
| `packages.<system>.trial-rootfs` | 一个最小系统，只为被检查而构建 |

ARM64 的引擎在 denial.cachix.org 上没有，构建要几小时。

两个 workflow，都是 `workflow_dispatch`：

| Workflow | Job |
|---|---|
| Nix Flake Check | **Evaluate the flake on AArch64** —— 几秒钟 |
| | **Resolve the AArch64 engine hashes** —— 只在勾了 `refresh_engine_hashes` 时跑。清空两个哈希再解析一次，报告 Nix 打印的 `got:` |
| Nix System Check | **Build a minimal NixOS system and check what it contains** —— 几小时 |

## 安装

每个目标都以相同的名字提供同样的三个包：`denial`、`denial-flutter-engine`
和 `denial-plugin-manager`。按上游所述，`denial-plugin-manager` 是可选的，
用于安装 Denial 插件。

```sh
# Debian / Ubuntu
sudo apt install ./denial-flutter-engine_*.deb ./denial_[0-9]*_*.deb
sudo apt install ./denial-plugin-manager_*.deb                    # 可选

# Arch
sudo pacman -U denial-flutter-engine-*.pkg.tar.gz denial-[0-9]*.pkg.tar.gz
sudo pacman -U denial-plugin-manager-*.pkg.tar.gz                  # 可选

# Fedora
sudo dnf install ./denial-flutter-engine-*.rpm ./denial-[0-9]*.rpm
sudo dnf install ./denial-plugin-manager-*.rpm                    # 可选

# openSUSE
sudo zypper install ./denial-flutter-engine-*.rpm ./denial-[0-9]*.rpm
sudo zypper install ./denial-plugin-manager-*.rpm                 # 可选

# Alpine
sudo apk add --allow-untrusted ./denial-flutter-engine-*.apk ./denial-[0-9]*.apk
sudo apk add --allow-untrusted ./denial-plugin-manager-*.apk     # 可选
```

### 用 Nix

flake 里带了 NixOS 模块和 overlay：

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
            programs.denial.plugins.enable = true; # 插件管理器
          }
        ];
      };
    };
}
```

重建系统，然后在你在用的显示管理器里选 **Denial**；模块不会启用显示管理器。
`programs.denial.package` 可以只换包而不换模块。

不在 NixOS 上时 overlay 就够：

```nix
nixpkgs.overlays = [ inputs.denial.overlays.default ];
environment.systemPackages = [
  pkgs.denial
  pkgs.denialPluginManager
];
```

ARM64 的引擎不在 `denial.cachix.org` 上——那个缓存只有上游的 x86_64 产物，架构不同 store
路径也不同，一个都命中不了。所以不需要配置它。代价是第一次会从源码编译引擎，要几小时。

## 许可证

GPL-3.0-or-later，见 [LICENSE](LICENSE)。