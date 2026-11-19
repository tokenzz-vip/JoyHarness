# 应用更新

JoyHarness 使用 SwiftPM 固定版本的 Sparkle 2.10.1，提供与 RcHarness 一致的原生检查、下载、签名校验和重启安装流程。应用不会静默安装更新；开启「自动检查更新」后，Sparkle 定期检查新版本，安装仍由用户确认。

## 用户行为

「设置」版本区的「检查更新…」由 Sparkle 显示结果。新版本按 `CFBundleShortVersionString` 做数字分段比较，例如 `0.2.10` 高于 `0.2.9`。相同展示版本即使构建号更高也不提示升级，避免本机构建号与 CI 运行编号混用导致误报。「版本历史」直接打开 GitHub Releases。

「自动检查更新」默认关闭，开关直接读写 Sparkle 的偏好。首次连接脚本启动成功后按钮才可用。更新失败详情只写入 `vip.tokenzz.joyharness` 的 `settings` 分类日志，不占用主面板操作提示。

## 更新源

当前安装包和更新源仅支持 Apple Silicon：

```text
https://github.com/tokenzz-vip/JoyHarness/releases/latest/download/appcast-arm64.xml
```

`appcast-arm64.xml` 指向同一 Release 中带版本的 DMG。README 中的固定 DMG 地址与带版本号 DMG 内容相同，方便首次安装；Sparkle 使用带版本地址，确保更新源和安装包一致。

## 签名密钥

Tokenzz 的 RcHarness 与 JoyHarness 共用一把 Sparkle Ed25519 签名密钥，避免多应用部署多份同等权限的长期私钥。公钥写在 `SUPublicEDKey`，应用要求更新源和更新包均通过 Ed25519 校验。本机私钥保存在登录钥匙串，生成工具使用的账户为 `vip.tokenzz.rcharness`。

首次导出到其他机器或 GitHub Actions 时，使用 Sparkle 自带的 `generate_keys` 工具：

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account vip.tokenzz.rcharness \
  -x "$RUNNER_TEMP/sparkle-private-key"
gh secret set SPARKLE_PRIVATE_KEY --repo tokenzz-vip/JoyHarness \
  < "$RUNNER_TEMP/sparkle-private-key"
rm -f "$RUNNER_TEMP/sparkle-private-key"
```

私钥不要提交到仓库、写入文档或输出到终端日志。需要轮换密钥时，先同时更新 JoyHarness 与 RcHarness 的 `SUPublicEDKey`，再更新仓库 secret 并发布新版本；旧应用只能验证旧公钥。

## 发布流程

Release 工作流在最终 DMG 完成 Developer ID 签名、Apple 公证和 stapling 后运行 `scripts/generate_update_feed.sh`。脚本从 DMG 读取应用元数据，生成全量更新项，写入 Ed25519 签名，再校验：

- appcast 文件名与应用内的固定更新地址一致；
- 展示版本与 Release 标签一致；
- 构建号、最低系统版本和下载大小来自实际交付的 DMG；
- 更新 URL 与本 Release 的具体 DMG 一致；
- appcast 与更新包的 Ed25519 签名有效。

发布附件包括带版本 DMG、固定名称 DMG、`appcast-arm64.xml` 和 `SHA256SUMS`。构建脚本把 Sparkle framework、XPC 服务和 Updater 辅助程序嵌入应用，裁剪为 arm64，并由内到外使用同一次 Developer ID 身份重新签名。
