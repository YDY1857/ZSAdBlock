# 蒙太奇影视 v1.8.5 正式注入库

包含旧 v8 去广告 hook，以及只在新版变身状态出现一次的欢迎弹窗。

变身判定：`flutter.7f5df8c5_d527649cacfdb0287553d9c1316d119a = 1`

## GitHub 网页上传

1. 先上传根目录的 `.gitattributes` 和 `README.md`。
2. 用 **Add file → Create new file** 创建 `ZSAdBlock/.keep`，进入该目录上传 `ZSAdBlock.m`、`welcome_popup.m` 和 `build.sh`。
3. 最后创建 `.github/workflows/.keep`，进入 `workflows` 目录上传 `build-dylib.yml`。
4. 打开 **Actions → Build ZSAdBlock.dylib → Run workflow**，下载 `ZSAdBlock-dylib` 产物。

两个 `.keep` 文件可以保留。

## 安装验证

1. 使用干净的新版 IPA 注入 `ZSAdBlock.dylib`，重签名并安装。
2. 未变身时不会显示欢迎弹窗。
3. 输入口令完成变身，杀掉 App 后台，再次打开。
4. 变身后弹出欢迎页；等待 10 秒后点击“进入应用”。
5. 以后启动不再显示。若倒计时结束前杀掉 App，下次仍会显示。
