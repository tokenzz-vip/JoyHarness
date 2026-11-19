# 本机交付约定

用户已授权：每次完成 JoyHarness 修改后，自动编译、安装到 `/Applications/JoyHarness.app`，并重新打开应用；直接执行，无需再次确认。

1. 运行与改动相应的检查；UI 改动使用 `--render-settings` 检查浅色、深色和最小窗口布局。
2. 使用 `zsh -ic 'scripts/build_app.sh .build/JoyHarness.app'` 构建，沿用脚本中的固定有效签名身份。身份不可用时报告阻碍，保留已安装版本。
3. 正常退出正在运行的 JoyHarness，将构建产物安装到 `/Applications/JoyHarness.app`，通过 `codesign --verify --deep --strict` 后重新打开，确认进程来自安装路径。
