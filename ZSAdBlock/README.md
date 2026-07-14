# 妆时手账 去广告 —— dylib 注入 + 重签名重打包（非越狱）

> 仅用于自有 / 已获授权应用的兼容性与去广告研究。

本方案不依赖越狱：把一个自定义 `ZSAdBlock.dylib` 注入到 App 主程序，运行时用
Objective-C runtime 交换（swizzling）拦截各广告 SDK 的**展示**方法，并对开屏做
UIWindow / UIView 双层兜底。核心原则是 **放行加载、只拦展示**，避免“无广告也卡开屏”。

- 目标 App：`com.dtz.zhuangshi`（妆时手账 v1.8.0）
- 主程序路径：`Payload/s5CCE1CA2A.app/s5CCE1CA2A`
- 广告栈：Sigmob WindMill（聚合）+ 腾讯优量汇/GDT + Sigmob 自有 + BeiZi

---

## 整体流程总览

```
① 编译 dylib（macOS/云端）        →  ZSAdBlock.dylib
② 放入 .app 目录                  →  Payload/s5CCE1CA2A.app/ZSAdBlock.dylib
③ 给主程序加载命令(LC_LOAD_DYLIB) →  注入
④ 重签名（App + dylib + 描述文件） →  可安装
⑤ 打包成 IPA                      →  妆时手账-noad.ipa
⑥ 真机安装                        →  完成
```

其中 ③④⑤ 有两种落地方式：
- **路线 1（推荐 Windows 用户）**：用 **Sideloadly** 一步完成注入+重签+安装。
- **路线 2（macOS 手动）**：`insert_dylib` + `codesign` + 手动打包。

---

## 第一步：编译 dylib

### macOS 本机
```bash
cd ZSAdBlock
chmod +x build.sh
./build.sh          # 产出 ZSAdBlock.dylib
```

### Windows 用户（无 Mac）→ GitHub Actions
1. 新建一个 GitHub 仓库，把本 `ZSAdBlock/` 目录推上去。
2. Actions 会按 `.github/workflows/build-dylib.yml` 自动在 macOS runner 上编译。
3. 进入该次 workflow 运行页，在 **Artifacts** 下载 `ZSAdBlock-dylib`，解压得到 `ZSAdBlock.dylib`。

> 也可用任意有 Xcode 的 Mac 帮你跑一次 `build.sh`。

---

## 路线 1：Sideloadly（Windows / macOS 都可，最省事）

Sideloadly 支持在侧载时自动“注入 dylib + 重签名”。

1. 先把已脱壳的 `Payload/` 重新压成 IPA：
   - 选中 **`Payload` 文件夹**（注意是文件夹本身），压缩为 zip，改名为 `妆时手账.ipa`。
   - Windows 可用 7-Zip：右键 `Payload` → 添加到压缩包 → 格式 zip → 得到 `Payload.zip` → 改名 `妆时手账.ipa`。
   - ⚠️ IPA 里的顶层必须是 `Payload/`，不要多套一层目录。
2. 打开 Sideloadly，把 `妆时手账.ipa` 拖进去。
3. 展开 **Advanced options**，勾选 **Inject dylib/framework/deb/bundle**，选择 `ZSAdBlock.dylib`。
   - Sideloadly 会自动执行 insert_dylib 并修正加载路径，无需手动。
4. 填入 Apple ID（免费或付费开发者账号都行），插上 iPhone，点 **Start**。
5. 首次安装后到 iPhone：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。
6. 打开 App 验证：开屏 / 插屏 / 激励 / 信息流广告应被拦截。

> AltStore 同理：先注入 dylib 再用 AltStore 安装，或用支持注入的分支。
> 免费账号签名 7 天过期，到期需重签；付费开发者账号 1 年。

---

## 路线 2：macOS 手动（insert_dylib + codesign）

需要：`insert_dylib`（`brew install insert_dylib` 或自行编译）、一个有效的签名证书与
描述文件（`.mobileprovision`）。

```bash
APP="Payload/s5CCE1CA2A.app"
BIN="$APP/s5CCE1CA2A"

# 1) 放入 dylib
cp ZSAdBlock/ZSAdBlock.dylib "$APP/ZSAdBlock.dylib"

# 2) 给主程序加载命令（@executable_path 指向 .app 根）
insert_dylib --inplace --all-yes \
  "@executable_path/ZSAdBlock.dylib" "$BIN"

# 校验已插入
otool -L "$BIN" | grep ZSAdBlock

# 3) 重签名（先 dylib，再整个 .app）
#    CERT 为你的证书名，如 "Apple Development: you@example.com (XXXXXXXXXX)"
CERT="Apple Development: you@example.com (XXXXXXXXXX)"

codesign -f -s "$CERT" "$APP/ZSAdBlock.dylib"

# 若有内嵌 framework，需逐个重签
for f in "$APP/Frameworks/"*.framework "$APP/Frameworks/"*.dylib; do
  [ -e "$f" ] && codesign -f -s "$CERT" "$f"
done

# 拷贝描述文件并用其 entitlements 重签主体
cp your.mobileprovision "$APP/embedded.mobileprovision"
security cms -D -i your.mobileprovision > /tmp/pp.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' /tmp/pp.plist > /tmp/ent.plist

codesign -f -s "$CERT" --entitlements /tmp/ent.plist "$APP"

# 4) 打包 IPA
mkdir -p out && rm -f out/妆时手账-noad.ipa
zip -qry out/妆时手账-noad.ipa Payload

# 5) 安装：Xcode Devices、ideviceinstaller、或再走 Sideloadly
ideviceinstaller -i out/妆时手账-noad.ipa
```

> Bundle ID 需与描述文件匹配；免费账号要把 `com.dtz.zhuangshi` 改成你自己
> 账号可用的 ID（同时改 Info.plist 的 CFBundleIdentifier），否则签名会失败。

---

## 验证与精修

安装后，dylib 会把日志写到 App 沙盒的 `tmp/ZSAdBlock.log`，其中包含：
- 启动期扫描到的所有“像广告”的类名（`[class-dump] ...`）；
- 实际被拦截的窗口 / 视图 / 方法。

若仍有个别广告漏网：
1. 从设备导出 `ZSAdBlock.log`（Xcode → Devices → 该 App → Download Container，
   或用 iMazing/爱思助手看沙盒 tmp）。
2. 把日志里新出现的广告类名 / selector 反馈回来。
3. 在 `ZSAdBlock.m` 的 `ZSAdClassNames()` / `ZSDisplaySelectors()` /
   `ZSKnownAdViewClasses()` 里补上对应项，重新编译即可。

---

## 常见问题

| 现象 | 原因 / 处理 |
|------|-------------|
| 装上闪退 | 证书/描述文件不匹配，或 framework 没逐个重签；检查 `codesign -dv`。|
| 无广告但开屏卡住 | 说明误拦了“加载”方法。本库刻意只拦展示；若你改过代码，确认没 hook load。|
| 广告偶尔仍出现 | SDK 类 lazy-load；已做 1.5s 二次补交换，仍漏则按日志补类名。|
| 装不上 / “无法验证 App” | 未信任开发者证书，或免费账号 7 天已过期，重签即可。|
| dylib 没生效 | `otool -L` 确认主程序含 `@executable_path/ZSAdBlock.dylib` 加载命令。|

---

## 文件清单
- `ZSAdBlock.m` —— 去广告注入源码（纯 ObjC runtime swizzling）
- `build.sh` —— macOS 本地编译脚本
- `.github/workflows/build-dylib.yml` —— 云端（GitHub Actions）编译
- `README.md` —— 本流程文档
