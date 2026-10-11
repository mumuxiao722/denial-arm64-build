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
gh variable set DENIAL_REF --body v0.6.0
```

所有缓存键都由它派生，所以换到新版本会让引擎缓存自动失效。其他地方都不需要改动。

## 使用补丁

```sh
git clone --branch v0.5.0 https://github.com/denialwm/denial.git denial
patches/denial-arm64-builder.sh denial
```

脚本锚定在所追踪 tag 所带的代码结构上，且是幂等的：运行两次会逐项报告已经打过补丁。
如果未来的发布改动了某个被锚定的代码块，脚本会报出它找不到的锚点并退出，而不是只应用
一半的改动。

## 构建

Fork 本仓库，在 Actions 页面运行工作流。它在 ARM64 runner 上构建，并把安装包作为工作流
产物上传；勾选 `publish_release` 则改为附到一个 GitHub release 上。

合成器和 Flutter 引擎作为独立的包发布，因此安装合成器不会顺带拉入引擎。

## 许可证

GPL-3.0-or-later，见 [LICENSE](LICENSE)。