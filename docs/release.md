# 发布 JoyHarness

JoyHarness 分别提供 Apple Silicon（`arm64`）和 Intel（`x86_64`）安装包，最低系统版本为 macOS 15。Release 工作流检查版本标签和签名配置，在对应架构的 runner 上构建应用并验证架构、版本和签名证书。两个 DMG 各自提交 Apple 公证并附加票据，再检查签名、镜像和 Gatekeeper 评估结果。两个构建任务都通过后，发布任务会合并并核对 SHA-256 清单，再上传附件到 GitHub Release。见 [Apple 的 macOS 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)。

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

| 架构 | 带版本号的安装包 | 最新版固定下载文件 |
| --- | --- | --- |
| Apple Silicon | `JoyHarness-v0.1.0-macos-arm64.dmg` | `JoyHarness-macos-arm64.dmg` |
| Intel | `JoyHarness-v0.1.0-macos-x86_64.dmg` | `JoyHarness-macos-x86_64.dmg` |

同一架构的两个 DMG 内容相同，`SHA256SUMS` 包含四个文件的 SHA-256 校验值。下载 DMG 和同一 Release 的 `SHA256SUMS` 到同一目录后，按实际文件名核对。例如 Intel 固定下载文件可以这样校验。

```bash
grep -F '  JoyHarness-macos-x86_64.dmg' SHA256SUMS | shasum -a 256 -c -
```

## 本地打包预览

使用已配置的本机签名身份构建，再生成含 `JoyHarness.app` 和「应用程序」快捷方式的 DMG。默认构建本机架构，可用 `JOY_HARNESS_ARCH=arm64` 或 `JOY_HARNESS_ARCH=x86_64` 显式指定。

```bash
zsh -ic 'scripts/build_app.sh .build/JoyHarness.app'
scripts/package_dmg.sh .build/JoyHarness.app .build/JoyHarness-preview.dmg
open .build/JoyHarness-preview.dmg
```

向 `main` 推送或发起拉取请求时，CI 会分别在 Apple Silicon 和 Intel 上运行测试并构建临时签名的预览 DMG。可在对应的 Actions 记录下载 `JoyHarness-ci-macos-arm64` 或 `JoyHarness-ci-macos-x86_64`。提供给用户下载的安装包由 Release 工作流签名和公证。
