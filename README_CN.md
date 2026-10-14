# denial-arm64-builder

[English](README.md)

[Denial](https://github.com/denialwm/denial) 是一个基于 Flutter 的 Wayland 合成器。
本仓库提供其 `tools/denial-pc` 构建系统的 ARM64 补丁；一个在 ARM64 runner 上构建打过
补丁的源码树、并把结果打包给五个发行版的 GitHub Actions 工作流；以及移植自上游的
Nix 打包。

上游 `denial-pc` 按 x86-64 配置，其构建系统无法在 ARM64 上原生运行。Denial 本身支持
ARM64 源码构建；上游缺少的是该脚本中的原生构建路径，以及发布 ARM64 二进制的流水线。
本仓库补齐这两项。

该补丁集最初在 [fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) 中开发，
当时位于 `.github/denial-arm64/` 目录下。现在它已独立出来，因此可以在运行受支持发行版的
ARM64 设备上，在满足上游宿主要求的前提下，使用该补丁集构建或安装 ARM64 版 Denial，
而不再绑定于 fedora-sheng。

## 状态

Denial 版本：`v0.5.0`

安装包发布在
[Releases 页面](https://github.com/mumuxiao722/denial-arm64-builder/releases)。

## 安装

每个目标提供三个包：`denial`、`denial-flutter-engine` 和 `denial-plugin-manager`。
`denial-plugin-manager` 为可选组件，用于安装 Denial 插件。

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

## 本地构建

在此构建的 Denial 版本由所检出的 tag 或 commit 决定。构建命令在 Denial 检出目录的根下
执行。

### 应用补丁

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
cd denial
git apply /path/to/denial-arm64-builder/patches/denial-arm64.diff
python3 /path/to/denial-arm64-builder/patches/arm64-prep.py prep-checkout .
```

请将本仓库的 `patches/` 目录与 Denial 检出目录并列放置。
`arm64-prep.py prep-checkout` 会创建 Denial 校验所需的 ARM64 prebuilt 元数据目录，
并改写两处指明 x86_64 的 Alpine 文件：`package-denial-apk` 按架构和摘要固定并构建的
minirootfs，以及决定所生成包声明支持何种架构的 `arch=` 声明。打过补丁的构建系统在
`gclient sync` 期间会再次以 `patch-deps` 参数调用同一文件，用以改写 sync 拉取的
`DEPS`，并剔除那一条 Flutter 仅为 linux-amd64 发布的 openjdk 依赖。

### 宿主依赖

编译 Denial 所需的工具由上游文档说明，见
[Host requirements](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#host-requirements)，
并可由 `tools/denial-pc doctor` 检查。各发行版的打包工具分别记录于
[Debian、Fedora 与 openSUSE](https://github.com/denialwm/denial/blob/v0.5.0/docs/BUILDING.md#debian-fedora-and-opensuse-package-adapters)
和 [Arch](https://github.com/denialwm/denial/blob/v0.5.0/docs/packaging/arch/README.md)。

这两份文档未提及的有两点。

五个目标都需要 `bsdtar`，而上游仅在 RPM 相关说明中提及它。deb 目标经
`verify-denial-native-package-metadata` 使用它，该脚本会检查它；APK 目标经
`package-denial-apk` 使用它。`tar` 无法替代：APK 由多个 gzip 流拼接而成，而 GNU tar
在第一个流之后停止，无法读取后续流中的 `.PKGINFO` 和签名。

Denial 无法在 Alpine 上编译，但可在 Alpine 这样的 musl 系统上运行。APKBUILD 只编译两个
小型 C 库；合成器、Flutter 引擎和插件管理器均在 glibc 宿主上预先构建，
`package-denial-apk` 将这份已 stage 的产物复制进精简的 Alpine 根文件系统，再组装成
`.apk`。该产物链接 glibc，因此在 Alpine 的 musl 上运行需要 `gcompat`。

### 构建步骤

```sh
./tools/denial-pc doctor      # 报告未满足的宿主要求
./tools/denial-pc bootstrap
./tools/denial-flutter-engine build
./tools/denial-pc build
```

## GitHub Actions 构建

工作流构建的 Denial 版本由 `denial_ref` 指定。

### Denial 版本

工作流每次运行构建一个 Denial tag，由 `denial_ref` 指定：

```sh
gh workflow run denial-arm64.yml -f denial_ref=v0.5.0
```

所有缓存键均由它派生，因此换一个版本会从空的引擎缓存开始，无需修改其他内容。

该字段用于在测试分支上验证新版本，而不改变 `main` 使用的 tag。不要用它改动默认版本：

```sh
gh workflow run denial-arm64.yml --ref bump-denial-<tag> -f denial_ref=<tag>
```

### 产物与 release

Fork 本仓库，在 Actions 页面运行 `Build Denial (ARM64)`。工作流在 ARM64 runner 上构建，
并将安装包作为工作流产物上传，默认保留七天；启用 `publish_release` 后，产物会附加到
GitHub release。这些产物是构建输出，不是软件源。

## Nix

`nix/` 是上游 Nix 打包的一份副本，在此提交，而非从 flake 输入导入。flake 固定
Denial `v0.5.0`，并另有一个 `plugins` 输入。上游那份仅在 `x86_64-linux` 上构建，
且没有 AArch64 引擎哈希；`nix/flutter-engine-lock.json` 记录了 AArch64 构建所需的
两个哈希，一个对应 Dart SDK，一个对应引擎源码闭包。

| 输出 | 内容 |
|---|---|
| `nixosModules.default` | NixOS 模块，`programs.denial.enable` |
| `overlays.default` | `denial`、`denialPluginManager`，以及引擎 |
| `packages.<system>.trial-rootfs` | 一个最小 NixOS 系统，用于测试安装 |

提供两个工作流：

| 工作流 | 作业 |
|---|---|
| Nix Flake Check | **在 AArch64 上评估 flake** |
|  | **解析 AArch64 引擎哈希** —— 仅在设置 `refresh_engine_hashes` 时运行。清空两个哈希并重新解析，报告 Nix 输出的 `got:`。 |
| Nix Install Check | **安装系统以测试 Denial 能否被安装** |

### 在 NixOS 上使用 Flake

在 NixOS 配置中声明 flake 输入，并导入 `nixosModules.default`：

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
              plugins.enable = true; # 可选
            };
          }
        ];
      };
    };
}
```

### 在非 NixOS 上使用 Nix 包管理器及 Flake

在 Nix 配置中声明 flake 输入。该 overlay 提供 `denial` 与 `denialPluginManager`：

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
              pkgs.denialPluginManager
            ];
          }
        ];
      };
    };
}
```

### 构建开销

AArch64 的引擎不在 `denial.cachix.org` 上：该缓存保存的是上游的 x86_64 产物，而不同架构
对应不同的 store 路径，因此没有任何缓存条目适用，也不需要额外配置。其代价是首次构建
需要从源码编译引擎，耗时数小时。

## 许可证

GPL-3.0-or-later，见 [LICENSE](LICENSE)。