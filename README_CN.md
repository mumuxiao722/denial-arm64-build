# denial-arm64-builder

[English](README.md)

为 ARM64 构建 [Denial](https://github.com/denialwm/denial)——一个基于 Flutter 的
Wayland 合成器——并打包给五个发行版。

上游的 `tools/denial-pc` 构建系统以 x86-64 为目标，不支持 ARM64。本仓库把它打补丁适配到
aarch64，使用源码构建的 Flutter 引擎，在 ARM64 CI runner 上完成构建，并上传产出的 RPM、
deb、APK 和 Arch 安装包。

这套补丁最初在 [fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) 中开发，位于
`.github/denial-arm64/` 目录下。现在移到这里，任何发行版都可以使用同一套补丁，而不必采用
该项目的镜像构建部分。

## 支持的 Denial 版本

本仓库只追踪一个 tag。被追踪的 ref 是仓库变量 `DENIAL_REF`：

```sh
gh variable set DENIAL_REF --body v0.5.0
```

| Denial tag | 补丁版本 |
| --- | --- |
| `v0.5.0` | 当前 |

所有缓存键都从该变量派生，所以切换到新版本会自动使引擎缓存失效。

## 使用方法

检出要构建的 Denial tag 并应用补丁：

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/denial-arm64-builder.sh denial
```

补丁集锚定在被追踪 tag 实际使用的代码形状上。脚本是幂等的：重复运行会逐项报告目标已打过
补丁。如果上游重构移动了任何一个带锚点的代码，脚本会报出找不到的锚点名称并退出，而不会只
应用一部分修改。

## 补丁覆盖范围

构建系统：

- `tools/denial-flutter-engine` —— aarch64 的 GN 参数、ARM64 构建路径、引擎检出的 DEPS 钩子
- `tools/denial-pc` —— aarch64 架构路径、对自建引擎的宽松引擎校验和处理
- `tools/stage-denial-runtime` —— 感知宿主 CPU 的 bundle 与引擎路径、宽松的引擎 SHA-256 校验
- `tools/prepare-denial-plugin-kit` —— 宽松的引擎校验和
- `patches/patch-deps.py` —— 在 `gclient sync` 期间应用

打包：

- `packaging/fedora/denial.spec` —— `ExclusiveArch` 包含 aarch64
- `packaging/opensuse/denial.spec` —— `ExclusiveArch` 包含 aarch64
- `tools/package-denial-rpm` —— 放宽的 RPM 通配符
- `tools/package-denial-deb` —— Debian 架构改为从 `uname -m` 推导，而不是写死 `amd64`，
  涵盖 control 字段和输出文件名
- `tools/package-denial-arch` —— 引擎校验和改为从宿主架构目录读取，不再写死
  `linux-x64-release`
- `packaging/arch/**/PKGBUILD` —— `arch=('x86_64' 'aarch64')`
- `tools/verify-denial-native-package-metadata` —— 接受 aarch64 的 RPM 架构

## ARM64 占位元数据

播种步骤会创建 `prebuilt/flutter-engine/linux-arm64-{debug,profile,release}/`，其中的
`args.gn`、`libflutter_engine.so.sha256`、`ENGINE_REVISION` 和 `FLUTTER_REVISION` 为空文件，
仅从 x86-64 目录复制许可与构建文档。Denial 自身的检查会与这些文件比较；补丁让基线为空时
跳过比较而不是失败。

## 构建

workflow 运行在 `ubuntu-24.04-arm` 上，手动触发，或在 `patches/` 变更时触发。它只有
`publish_release`（默认关闭）一个输入项，其余全部从 `DENIAL_REF` 派生。

只维护一份缓存：

- `denial-engine-cache-<ref>` —— 编译完成的 `libflutter_engine.so` 以及配套的构建状态，
  在 `denial-flutter-engine build` 之后立即保存。

只缓存引擎的最终产物。Skia 的中间对象有几十 GB，超出仓库 10 GB 的缓存配额，因此每次
运行都会重编；Rust 二进制和 Flutter bundle 同理。所以一次运行大约在引擎上花 40 分钟、
在 `denial-pc build` 上再花 50 分钟，之后才进入打包。缓存省下的是最后的链接和打包步骤，
不是主体编译。

打包目标，全部来自同一份 staging 产物。Fedora 和 openSUSE 产出相同的 RPM 文件名，因此
打包时用目录区分，上传时用 artifact 名区分：

| 命令 | 上传为 | 匹配路径 |
| --- | --- | --- |
| `denial-pc fedora-package` | `denial-rpm-fedora-arm64` | `packages/denial-[0-9]*.rpm` |
| `denial-pc opensuse-package` | `denial-rpm-opensuse-arm64` | `packages/opensuse/denial-[0-9]*.rpm` |
| `denial-pc debian-package` | `denial-deb-arm64` | `packages/*.deb` |
| `denial-pc alpine-package` | `denial-apk-arm64` | `packages/*.apk` |
| `denial-pc arch-package` | `denial-arch-arm64` | `packages/*.pkg.tar.zst` |

RPM 和 deb 的匹配模式只覆盖合成器本体；Flutter engine 作为独立包发布。因此每个 RPM 目标
还会上传第二个 artifact：

| Artifact | 匹配路径 |
| --- | --- |
| `denial-flutter-engine-rpm-fedora-arm64` | `packages/denial-flutter-engine-*.rpm` |
| `denial-flutter-engine-rpm-opensuse-arm64` | `packages/opensuse/denial-flutter-engine-*.rpm` |

## 使用者

`mumuxiao722/fedora-sheng` 在其 `.github/denial-arm64/` 下保留了这份补丁集的副本，并在
`build-denial` job 中应用它，为 Xiaomi Pad 6S Pro 镜像产出可安装的 RPM。

## 许可

GPL-3.0-or-later，见 [LICENSE](LICENSE)。