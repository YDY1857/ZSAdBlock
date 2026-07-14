# ZSAdBlock —— 妆时手账 去广告（重签名重打包用）

本仓库用于在云端编译 iOS 去广告注入库 `ZSAdBlock.dylib`，随后通过 Sideloadly 注入
并重签名安装到真机（非越狱）。

- `ZSAdBlock/ZSAdBlock.m` —— 去广告源码（纯 Objective-C runtime swizzling，放行加载、只拦展示）
- `ZSAdBlock/build.sh` —— 本地编译脚本
- `ZSAdBlock/README.md` —— 注入 / 重签名 / 重打包完整流程
- `.github/workflows/build-dylib.yml` —— GitHub Actions 云端编译（macOS runner）

## 快速开始

1. 按 `GitHub网页上传与运行步骤.md`，通过网页分别建立目录并上传文件（Actions 自动编译 dylib）。
2. 在 Actions 运行页下载 Artifact `ZSAdBlock-dylib`（得到 `ZSAdBlock.dylib`）。
3. 用 [Sideloadly](https://sideloadly.io/) 注入 dylib 并侧载安装。
   GitHub 网页上传步骤见 `GitHub网页上传与运行步骤.md`，注入步骤见 `ZSAdBlock/README.md`。

> 仅用于自有 / 已获授权应用的兼容性与去广告研究。
