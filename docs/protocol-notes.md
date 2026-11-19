# 协议依据与边界

调研日期：2026-11-03。二代协议没有 Nintendo 官方公开规范，以下为原作者发布的逆向资料，字段和流程用独立 Swift 实现，不引入其驱动或运行时。

- [Nintendo Switch Bluetooth HID notes](https://github.com/dekuNukem/Nintendo_Switch_Reverse_Engineering/blob/master/bluetooth_hid_notes.md)：一代 `0x01` 子命令、`0x21` 应答、`0x30` 完整报告和按键字段。应用将报告规范化为包含 ID 的字节数组；初始化选择 `0x30`。不将侧握的 `0x3f` 简化报告误解析为完整布局。
- [linux-switch2 PROTOCOL.md](https://github.com/novakpetya/linux-switch2/blob/main/PROTOCOL.md)：二代广播厂商 ID `0x0553`、VID `0x057e`、PID `0x2067` 左 / `0x2066` 右、原生 GATT 特征、63 字节原生输入、二代独立位布局、8 字节命令头、初始化输入屏障和 10ms 命令间隔。
- [seitanmen/Joycon2forMac](https://github.com/seitanmen/Joycon2forMac)：macOS CoreBluetooth 接收二代通知的可行性参考。没有复制其虚拟 HID 实现。
- [SDL controller identities](https://github.com/libsdl-org/SDL/blob/main/src/joystick/controller_list.h)：两代左右 PID 交叉确认。

## 二代实现

CoreBluetooth 厂商数据包含公司 ID 两字节，因此匹配 `53 05 01 00 03 7e 05` 后读取 PID。未知外设、Pro 手柄和一代不会进入二代连接路径。

只订阅侧别对应的原生输入特征以及基本命令应答。输入特征的值不带 HID report ID；若把一代字段偏移套在二代上，会把 A/B、方向键、肩键与摇杆解错。

初始化包含 BLE preamble、初始 feature mask、输入模式选择、真实输入屏障、原始 selector、最终 buttons+sticks feature mask、握把键启用和 LED。逐命令匹配应答命令和子命令，检查成功位；其他有应答的命令最多发送三次。若后续还需使用同一命令和子命令，先发的那次超时就结束初始化，避免重发产生的延迟应答被误认成后续命令的应答。写入完成不视为协议应答。订阅失败、写入失败、应答拒绝、超时均报告给界面。初始化完成且获得有效输入后才对外分发按键。

最终 mask 只请求按键和摇杆；校准中心支持用户手动记录。没有声称实现完整 Linux 驱动的 IMU、SPI 出厂范围校准、NFC 或光学鼠标流程。公开参考中的完整序列还包含校准和固件查询；本应用精简序列是否适用于不同固件，需要实体二代手柄验证。

## 一代实现

设备发现仅匹配一代左右 VID/PID。每只设备保留报告缓冲区、初始化队列和独立身份，输出命令含报告 ID 及中性震动字节。完整报告按钮和共享按钮按侧别过滤，避免把另一侧填充值视为输入。系统未提供序列号时，应用尝试读取设备信息中的蓝牙地址作为重连标识，字段依据 [Linux HID Nintendo 驱动](https://raw.githubusercontent.com/torvalds/linux/master/drivers/hid/hid-nintendo.c)。地址不可用时仍可手动选择手柄。

使用 IOHID 非独占读取，没有修改全局 hidutil 键映射。权限或其他系统手柄服务可能影响访问，需 macOS 实机验收。

## 来源代码

`SystemEventSender.swift`、`SettingsStorage.swift` 和 `SingleInstanceLock.swift` 基于用户指定的同级 RcHarness 项目，其 MIT 许可保留在 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。其他 Joy-Con 协议逻辑为本项目实现。
