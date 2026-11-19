# 发布 JoyHarness

JoyHarness 的 macOS 安装包面向 Apple Silicon，最低系统版本为 macOS 15。发布工作流从版本标签构建应用，验证架构和版本，使用 Developer ID 签名应用与 DMG，再将 DMG 提交 Apple 公证。公证票据附加到 DMG 后，工作流校验签名、镜像和 Gatekeeper 评估结果，再发布 GitHub Release。见 [Apple 的 macOS 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)。

## 首次配置

在 JoyHarness 的 GitHub 仓库设置中打开 **Secrets and variables → Actions → Repository secrets**，添加以下值。证书需包含私钥，签名身份与 Apple 公证凭据需属于同一个开发者团队。

| Secret | 值 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application 证书和私钥导出的 `.p12`，经 Base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `JOY_HARNESS_SIGNING_IDENTITY` | 完整证书名称，格式为 `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | 用于公证的 Apple 账户邮箱 |
| `APPLE_TEAM_ID` | Apple Developer 团队 ID |
| `APPLE_APP_PASSWORD` | Apple 账户的 App 专用密码 |

## 发布新版本

1. 将准备发布的代码和工作流提交并推送到 GitHub，确认 CI 通过。将 `Sources/JoyHarness/Info.plist` 的展示版本同步到准备发布的版本，便于本机构建显示相同版本。正式发布的展示版本取自标签，构建号取自 Release 工作流的运行编号。
2. 在发布提交上创建并推送 `vMAJOR.MINOR.PATCH` 标签，例如 `v0.1.0`。

   ```bash
   git tag -a v0.1.0 -m "JoyHarness v0.1.0"
   git push origin v0.1.0
   ```

3. 在 GitHub Actions 查看 **Release** 的运行结果。GitHub 会生成发布说明，工作流将附件上传到草稿，全部上传后公开版本。

如配置或公证失败，可在 **Actions → Release → Run workflow** 输入已经存在的标签重试。草稿只包含本次预期附件时可复用。若有其他草稿附件，请检查后再重试。已公开版本的附件应保留，后续修改使用新标签。

| 发布附件 | 用途 |
| --- | --- |
| `JoyHarness-v0.1.0-macos-arm64.dmg` | 对应具体版本的安装包 |
| `JoyHarness-macos-arm64.dmg` | 与带版本号的 DMG 内容相同，供 README 固定下载链接使用 |
| `SHA256SUMS` | 上述两个文件的 SHA-256 校验值 |

下载一个 DMG 和同一 Release 的 `SHA256SUMS` 到同一目录后，在该目录运行以下命令核对文件。

```bash
grep -F '  JoyHarness-macos-arm64.dmg' SHA256SUMS | shasum -a 256 -c -
```

## 本地打包预览

使用已配置的本机签名身份构建，再生成含 `JoyHarness.app` 和「应用程序」快捷方式的 DMG。

```bash
zsh -ic 'scripts/build_app.sh .build/JoyHarness.app'
scripts/package_dmg.sh .build/JoyHarness.app .build/JoyHarness-preview.dmg
open .build/JoyHarness-preview.dmg
```

CI 也会生成临时签名的预览 DMG，供构建检查。提供给用户下载的安装包由 Release 工作流签名和公证。
