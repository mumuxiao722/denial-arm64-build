# denial-arm64-builder

[English](README.md)

[Denial](https://github.com/denialwm/denial) 是一个基于 Flutter 的 Wayland
合成器。本仓库提供其 `tools/denial-pc` 构建系统的 ARM64 补丁，以及一个
GitHub Actions 工作流——在 ARM64 runner 上构建打过补丁的源码树，并把结果打包给
五个发行版。

上游 `denial-pc` 以 x86-64 为目标，不支持 ARM64。本仓库为该构建系统及其打包适配器
补充 aarch64 支持，并提供一个把 Denial tag 转换为 RPM、deb、APK 和 Arch 安装包的
工作流。

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
minirootfs 换成 aarch64；打过补丁的构建系统会用同一个文件、传入 `patch-deps`
参数，去改写 `gclient sync` 拉取的 `DEPS`。

这个 diff 包含针对 `v0.5.0` 的全部改动，所以打完之后用 `git diff` 就能看清它做了什么。

## 宿主工具

构建阶段需要一套 C++ 与 Flutter 工具链：CMake、Ninja、pkg-config、Rust，以及
EGL、GL、GBM、GLES、SDL2、input、udev、xkbcommon、seat、GLib、GTK 和 fontconfig
的开发头文件。按你自己的发行版方式装即可。

还需要 `bsdtar`，四个打包脚本里有三个要它。`tar` 替代不了：一个 APK 是好几段 gzip 流
拼起来的，而 GNU tar 读到第一段就停，看不到后面流里的 `.PKGINFO` 和签名。

Rust 要两步：先装 `rustup`，再跑 `rustup default stable`，之后确保 `cargo` 在 `PATH` 里。

每个打包脚本都会检查自己需要的工具，缺一个就退出，所以这就是它检查的清单：

| 目标 | 需要 |
|---|---|
| Fedora、openSUSE | `rpmbuild`、`rpm`、`rpm2cpio` |
| Debian、Ubuntu | `dpkg-deb` |
| Arch | `makepkg`、`pacman` |
| Alpine | `bwrap` |

APK 是给 Alpine 用的，但不是在 Alpine 上构建的。`package-denial-apk` 会下载一个
Alpine 根文件系统，用 `bwrap` 在里面跑 `abuild`，所以构建过程本身是在普通的 glibc
宿主上进行的。产出包的运行时依赖里有 `gcompat`，因为 Alpine 用的是 musl libc，这个包
需要 glibc 兼容层。

## 构建

Fork 本仓库，在 Actions 页面运行工作流。它在 ARM64 runner 上构建，并把安装包作为工作流
产物上传，保留七天；勾选 `publish_release` 则改为附到一个 GitHub release 上。
这些产物是构建输出，不构成软件源。

## 安装

合成器和 Flutter 引擎作为独立的包发布，但两者并不互相独立：下面每个发行版里，
合成器都依赖引擎，装它就会把引擎一起拉进来。两个包一起给，让包管理器自己解析即可。

| 发行版 | 合成器 | 引擎 | 插件管理 |
|---|---|---|---|
| Debian / Ubuntu | `denial` | `denial-flutter-engine` | `denial-plugin-manager`，可选 |
| Fedora / openSUSE | `denial` | `denial-flutter-engine` | `denial-plugin-manager`，可选 |
| Arch | `denial` | `denial-flutter-engine` | `denial-plugin-manager`，可选 |
| Alpine | `denial` | `denial-flutter-engine` | `denial-plugin-manager`，可选 |

按上游所述，`denial-plugin-manager` 是可选软件包，用于安装 Denial 插件。

```sh
# Arch。引擎包名里 makepkg 原本用冒号分隔 epoch，产物不允许含冒号，故为 +。
# pacman 从包内部读版本，文件名不影响安装。
sudo pacman -U denial-flutter-engine-*.pkg.tar.gz denial-*.pkg.tar.gz
sudo pacman -U denial-plugin-manager-*.pkg.tar.gz                  # 可选

# Fedora
sudo dnf install ./denial-flutter-engine-*.rpm ./denial-*.rpm
sudo dnf install ./denial-plugin-manager-*.rpm                    # 可选

# openSUSE
sudo zypper install ./denial-flutter-engine-*.rpm ./denial-*.rpm
sudo zypper install ./denial-plugin-manager-*.rpm                 # 可选

# Debian / Ubuntu
sudo apt install ./denial-flutter-engine-*.deb ./denial-*.deb
sudo apt install ./denial-plugin-manager-*.deb                    # 可选

# Alpine
sudo apk add --allow-untrusted ./*.apk
sudo apk add --allow-untrusted ./denial-plugin-manager-*.apk     # 可选
```

安装会写入 `/usr/share/wayland-sessions/denial.desktop`，因此 Denial 会出现在你当前
使用的显示管理器的会话选择器里。

## 许可证

GPL-3.0-or-later，见 [LICENSE](LICENSE)。