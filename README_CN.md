# denial-arm64-build

[English](README.md)

[Denial](https://github.com/denialwm/denial) 合成器的 ARM64 构建支持。Denial 是一个
基于 Flutter 的 Wayland 合成器。

上游的 `tools/denial-pc` 构建系统以 x86-64 为目标，不支持 ARM64。本仓库保存让 Denial
能在 aarch64 上使用源码构建的 Flutter 引擎进行构建的补丁，使产物可以安装在 ARM64 硬件上。

这些补丁最初在 [fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) 中开发，位于
`.github/denial-arm64/` 目录下。现在移到这里，任何发行版都可以使用同一套补丁，而不必采用
该项目的镜像构建部分。

## 支持的 Denial 版本

| Denial tag | 补丁版本 |
| --- | --- |
| `v0.5.0` | 当前 |

## 使用方法

检出要构建的 Denial tag 并应用补丁：

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/patch-denial-arm64.sh denial
```

脚本是幂等的：重复运行会逐项报告目标已打过补丁。每处替换都带有锚点检查，如果上游重构移动了
被打补丁的代码，脚本会报出找不到的锚点名称并退出，而不会只应用一部分修改。

## 补丁覆盖范围

- `tools/denial-flutter-engine` —— aarch64 的 GN 参数、ARM64 构建路径、引擎检出的 DEPS 钩子
- `tools/denial-pc` —— aarch64 架构路径、对自建引擎的宽松引擎校验和处理
- `tools/stage-denial-runtime` —— 感知宿主 CPU 的 bundle 与引擎路径、宽松的引擎 SHA-256 校验
- `tools/prepare-denial-plugin-kit` —— 宽松的引擎校验和
- `tools/package-denial-rpm` —— 放宽的 RPM 通配符
- `packaging/fedora/denial.spec` —— `ExclusiveArch` 包含 aarch64
- `tools/verify-denial-native-package-metadata` —— 接受 aarch64 的 RPM 架构

`patches/patch-deps.py` 由引擎补丁在 `gclient sync` 期间调用。

## ARM64 占位元数据

播种步骤会创建 `prebuilt/flutter-engine/linux-arm64-{debug,profile,release}/`，其中的
`args.gn`、`libflutter_engine.so.sha256`、`ENGINE_REVISION` 和 `FLUTTER_REVISION` 为空文件，
仅从 x86-64 目录复制许可与构建文档。Denial 自身的检查会与这些文件比较；补丁让基线为空时
跳过比较而不是失败。

## 使用者

`mumuxiao722/fedora-sheng` 在其 `build-denial` job 中应用本补丁集并产出可安装的 RPM。它会
检出本仓库并对它的 Denial 检出运行 `patches/patch-denial-arm64.sh`，而不再自带副本。

## 许可

GPL-3.0-or-later，见 [LICENSE](LICENSE)。