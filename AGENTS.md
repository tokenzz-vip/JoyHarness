# AGENTS.md

JoyHarness 是原生 macOS 菜单栏应用，使用 SwiftPM、AppKit 和 SwiftUI。一代 Joy-Con 通过 IOHID 接入，二代通过 CoreBluetooth BLE 接入。

## 环境

- Apple Silicon、macOS 15+、Xcode 16+（Swift 6 工具链，语言模式 v5）。
- Sparkle 用于应用内更新，版本固定在 `Package.swift`。

## 常用命令

```bash
scripts/test_all.sh   # Swift 测试、Shell / Python 脚本语法和 Info.plist 检查
swift test           # 仅 Swift 测试，可用 --filter 选择测试
zsh -ic 'scripts/build_app.sh .build/JoyHarness.app'
```

改动 UI 后，从构建产物运行 `--render-settings` 导出并查看截图，检查浅色、深色及最小窗口布局。渲染使用临时配置，无需连接手柄。

```bash
.build/JoyHarness.app/Contents/MacOS/JoyHarness --render-settings /tmp/joyharness-light
.build/JoyHarness.app/Contents/MacOS/JoyHarness --render-settings /tmp/joyharness-dark --dark
.build/JoyHarness.app/Contents/MacOS/JoyHarness --render-settings /tmp/joyharness-narrow --narrow
```

## 本机编译与安装

用户已授权每次完成 JoyHarness 修改后自动编译、安装并重新打开应用，直接执行，无需再次确认。

1. 运行与改动相应的检查。UI 改动按上节检查构建产物的截图，再安装。
2. 用上面的 `zsh -ic` 命令构建，以加载 `~/.zshrc` 中的签名配置。脚本优先使用 `JOY_HARNESS_LOCAL_SIGNING_IDENTITY`，未配置时沿用 `RC_HARNESS_LOCAL_SIGNING_IDENTITY`。本机交付使用固定的有效证书。身份缺失或无效时报告阻碍，保留已安装版本。
3. 正常退出正在运行的 JoyHarness，确认进程退出后将构建产物安装到 `/Applications/JoyHarness.app`。
4. 运行 `codesign --verify --deep --strict /Applications/JoyHarness.app`。通过后从该路径重新打开，确认运行进程的可执行文件为 `/Applications/JoyHarness.app/Contents/MacOS/JoyHarness`。

## 开发约定

- 设备回调和输入状态机在主线程运行，沿用 `@MainActor`。两代传输通过 `ControllerTransport` 接入，设备型号定义集中在 `JoyConProfile`。
- 只有选中的物理手柄可以触发映射。同型号设备按物理 ID 区分，断线后保留选择。改动设备切换、断线、暂停、休眠或方案切换时，验证旧的按住动作得到释放。
- 合成键盘和鼠标事件通过 `SystemEventSender` 发出。测试捕获 `InputEngine` 的输出回调，避免向桌面发送事件。定时逻辑复用 `CommandQueue.Scheduler`，测试用 `TestClock` 推进时间。
- 配置继续使用 `JoyHarness.` 键前缀，JSON 通过 `SettingsStorage` 读写。改动配置结构或内置预设时，验证旧配置和导入文件能保留已有绑定。
- 设置界面复用 `SettingsStyle.swift` 和 `SettingsComponents.swift` 中的样式与组件。运行时日志使用 `Log`（`os.Logger`）。

## 文档

- 构建环境、使用方法和排查见 [README.md](README.md)。
- 界面或运行时行为变化时同步更新 [行为说明](docs/behavior.md)。改动设备接入或报告解析时同时查阅 [协议依据](docs/protocol-notes.md) 和行为说明中的硬件验收清单。
- 改动发布打包、签名或公证时查阅 [发布说明](docs/release.md)。改动 Sparkle 或更新源时查阅 [应用更新说明](docs/app-updates.md)。
