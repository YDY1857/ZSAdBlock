# 新版变身状态诊断

这是一次性诊断 dylib，只读取并对比 `NSUserDefaults`，不会修改 App 的变身数据，也不包含正式欢迎弹窗。

## 编译

如果 GitHub 网页不能直接上传文件夹：

1. 先上传根目录的 `.gitattributes` 和 `README.md`。
2. 用 **Add file → Create new file** 创建 `TransformDiagnostic/.keep`，然后进入该目录上传 `build.sh` 和 `TransformDiagnostic.m`。
3. 最后创建 `.github/workflows/.keep`，进入 `workflows` 目录上传 `build-diagnostic.yml`。
4. 打开 **Actions → Build TransformDiagnostic.dylib → Run workflow**，完成后下载 `TransformDiagnostic-dylib`。

两个 `.keep` 文件可以保留，不影响编译。

## 真机操作

1. 删除手机上现有 App，使用当前目录中的干净新版 IPA 注入 `TransformDiagnostic.dylib`、重签名并安装。
2. 首次打开后保持在未变身界面约 7 秒，看到“新版诊断：基准已保存”后点“关闭”。
3. 输入变身口令，杀掉 App 后台；不要卸载、覆盖安装或重新注入。
4. 再次打开同一个 App，等待约 7 秒。
5. 在“新版变身状态诊断结果”中点击“复制完整结果”，把文字发回 Codex。

含 token、密码、Cookie、认证、会话、手机号、邮箱和常见设备标识的键会被排除；其他复杂值只显示类型和数量。
