import AppKit
import SwiftUI

@MainActor
struct HarnessRootView: View {
    let model: DashboardModel
    @ObservedObject var setup: SetupFlow

    var body: some View {
        if setup.isPresented {
            SetupView(model: model, setup: setup)
        } else {
            DashboardView(model: model)
        }
    }
}

@MainActor
struct SetupView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var setup: SetupFlow

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.sections) {
                    VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                        Text(setup.step.title).font(SettingsStyle.Typography.pageTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    content
                }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(SettingsStyle.pagePadding)
                .frame(maxWidth: .infinity)
            }
            .id(setup.step)
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .tint(model.colorMode.palette.selectionTint)
        .environment(\.appColorMode, model.colorMode)
        .preferredColorScheme(model.themeMode.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
        .overlay(alignment: .topTrailing) {
            if let notice = model.notices.last(where: { $0.issue == .configurationSave }) {
                DashboardNoticeView(notice: notice) { model.dismissNotice(notice.id) }
                    .padding(.top, 122)
                    .padding(.trailing, SettingsStyle.pagePadding)
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 0) {
            ForEach(SetupStep.allCases) { step in
                stepButton(step)
            }
        }
        .background(alignment: .top) {
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(SetupStep.allCases.count)
                ForEach(0..<(SetupStep.allCases.count - 1), id: \.self) { index in
                    Capsule()
                        .fill(index < setup.step.index ? model.colorMode.palette.selectionTint : Color.primary.opacity(0.14))
                        .frame(width: max(0, width - 44), height: 2)
                        .position(x: CGFloat(index + 1) * width, y: 15)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 800)
        .padding(.horizontal, SettingsStyle.pagePadding)
        .padding(.top, 36)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置向导进度")
    }

    private func stepButton(_ step: SetupStep) -> some View {
        let current = step == setup.step
        let previous = step.index < setup.step.index
        let style = current ? Color.white : previous ? model.colorMode.palette.selectionTint : Color.secondary
        return Button {
            setup.goBack(to: step)
        } label: {
            VStack(spacing: SettingsStyle.Spacing.inline) {
                Group {
                    if previous {
                        Image(systemName: "checkmark")
                    } else {
                        Text("\(step.index + 1)").monospacedDigit()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style)
                .frame(width: 30, height: 30)
                .background(current ? model.colorMode.palette.actionTint : Color(nsColor: .controlBackgroundColor), in: Circle())
                .overlay { Circle().strokeBorder(previous ? model.colorMode.palette.selectionTint : Color.primary.opacity(0.14)) }
                Text(step.title).font(.system(size: 12, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!previous)
        .accessibilityLabel("第 \(step.index + 1) 步，\(step.title)")
        .accessibilityValue(current ? "当前步骤" : previous ? "可返回" : "待完成")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private var footer: some View {
        let hint = setup.blockingHint(model.setupReadiness)
        return VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
            if let hint {
                Label(hint, systemImage: "info.circle").foregroundStyle(.secondary)
                    .font(SettingsStyle.Typography.body)
            }
            HStack(spacing: SettingsStyle.Spacing.controls) {
                if setup.step != .welcome {
                    Button("上一步") { setup.goBack(to: SetupStep.allCases[setup.step.index - 1]) }
                }
                Text("第 \(setup.step.index + 1) 步，共 \(SetupStep.allCases.count) 步")
                    .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button(setup.completed ? "返回设置" : "稍后设置", action: model.pauseSetup)
                    .keyboardShortcut(.cancelAction)
                Button(continueTitle, action: model.advanceSetup)
                    .buttonStyle(SettingsActionButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(hint != nil)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 800)
        .padding(SettingsStyle.pagePadding)
        .frame(maxWidth: .infinity)
    }

    private var continueTitle: String {
        switch setup.step {
        case .welcome: "开始设置"
        case .complete: "开始使用"
        default: "继续"
        }
    }

    private var subtitle: String {
        switch setup.step {
        case .welcome: "连接 Joy-Con，用手柄操作常用应用、快捷键和鼠标。"
        case .permissions: "选择手柄型号，然后开启对应的 macOS 权限。"
        case .controller: "按当前型号的步骤连接手柄，从下拉菜单确认要使用的设备。"
        case .voice: "如果你使用听写或语音输入工具，可以让手柄触发它的快捷键。"
        case .trial: "试一下实体按键和摇杆，观察示意图上的实时反馈。"
        case .complete: "确认当前手柄与默认键位方案，然后打开按键映射。"
        }
    }

    @ViewBuilder private var content: some View {
        switch setup.step {
        case .welcome:
            SettingsPanel {
                HStack(spacing: SettingsStyle.Spacing.sections) {
                    Image(nsImage: BrandAssets.applicationIcon)
                        .resizable().scaledToFit().frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
                        Text("开始使用 JoyHarness").font(SettingsStyle.Typography.panelTitle)
                        Text("准备一只 Joy-Con 或 Joy-Con 2。向导会带你开启权限、连接手柄并试用按键。")
                        Text("设置自动保存在本机，稍后可从设置页或菜单栏继续。").foregroundStyle(.secondary)
                    }
                }
            }
        case .permissions: permissions
        case .controller: controller
        case .voice: voice
        case .trial: trial
        case .complete:
            SettingsPanel("当前配置", symbol: "checkmark.circle") {
                LabeledContent("当前手柄", value: model.controllerTitle)
                LabeledContent("连接状态") { connectionStatus }
                LabeledContent("默认键位方案", value: model.defaultProfile.name)
                Text("你可以从菜单栏暂停映射、切换手柄或再次打开设置向导。").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var permissions: some View {
        VStack(spacing: SettingsStyle.Spacing.groups) {
            SettingsPanel("手柄型号", symbol: "gamecontroller") {
                controllerMenu
            }
            SettingsPanel("所需权限", symbol: "lock.shield") {
                SettingsPermissionRow("辅助功能", detail: "向当前应用发送键盘与鼠标操作", symbol: "hand.raised",
                                      granted: model.accessibility, action: model.requestAccessibility)
                if let profile = model.controllerSelection.profile {
                    Divider()
                    if profile.generation == .first {
                        SettingsPermissionRow("输入监控", detail: "接收一代 Joy-Con 的按键与摇杆输入", symbol: "keyboard",
                                              granted: model.inputMonitoring, action: model.requestInputMonitoring)
                    } else {
                        SettingsPermissionRow("蓝牙", detail: "发现并连接 Joy-Con 2", symbol: "antenna.radiowaves.left.and.right",
                                              granted: model.bluetoothGranted) { model.openPrivacy("Privacy_Bluetooth") }
                    }
                }
                Divider()
                HStack {
                    Text("返回 JoyHarness 后会自动刷新。若 macOS 提示重新打开应用，退出后可继续此步骤。")
                        .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新权限状态", action: model.refreshPermissions)
                }
            }
        }
    }

    private var controller: some View {
        let firstGeneration = model.controllerProfile.generation == .first
        return VStack(spacing: SettingsStyle.Spacing.groups) {
            SettingsPanel("配对与连接", symbol: "gamecontroller") {
                controllerMenu
                Text(firstGeneration
                     ? "在手柄侧轨长按 SYNC，等绿色指示灯来回闪烁，再到 macOS 蓝牙设置中选择 \(model.controllerProfile.name)。"
                     : "在手柄侧轨长按 SYNC，等绿色指示灯来回闪烁，再点击「重新扫描」。JoyHarness 会通过蓝牙连接手柄。")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if firstGeneration { Button("打开蓝牙设置", action: model.openBluetoothSettings) }
                    Button("重新扫描", action: model.rescan)
                }
            }
            SettingsPanel("连接详情", symbol: "antenna.radiowaves.left.and.right") {
                Text(firstGeneration ? model.hidStatus : model.bleStatus)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var controllerMenu: some View {
        ControllerDeviceMenu(model: model) {
            HStack(spacing: SettingsStyle.Spacing.inline) {
                Text(model.controllerTitle)
                if let status = model.controllerConnectionStatus {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.selectedDeviceReady ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(status)
                            .font(SettingsStyle.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .padding(SettingsStyle.compactControlPadding)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsStyle.controlRadius).strokeBorder(.primary.opacity(0.14)) }
        }
    }

    private var connectionStatus: some View {
        SettingsStatus(title: model.controllerConnectionStatus ?? "未连接",
                       color: model.selectedDeviceReady ? .green : .secondary)
    }

    private var voice: some View {
        let controllerID = model.controllerProfile.id
        return SettingsPanel("语音按键", symbol: "keyboard") {
            SettingsPreference(symbol: "mic", title: model.controllerTitle,
                               detail: "此设置适用于当前型号的所有键位方案。") {
                Picker("语音按键", selection: Binding(get: { model.voiceInput }, set: model.setVoiceInput)) {
                    Text("未设置").tag(nil as ControllerInput?)
                    ForEach(model.voiceInputChoices) { input in
                        Text(input.label).tag(Optional(input))
                    }
                }
                .labelsHidden()
                .accessibilityLabel("语音按键")
            }
            if let input = model.voiceInput {
                Divider()
                VoiceButtonModeOptions(button: Binding(
                    get: { model.voiceButton },
                    set: { button in
                        guard button.input == input else { return }
                        _ = model.saveVoiceButton(button, controllerID: controllerID)
                    }
                ), sideBySide: true)
                .id(input)
                .id(controllerID)
            }
            Text("请在语音工具中设置相同的触发快捷键，并选择 Mac 或已接入的麦克风。")
                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
        }
    }

    private var trial: some View {
        HStack(alignment: .top, spacing: SettingsStyle.Spacing.sections) {
            SettingsPanel {
                JoyConArtwork(side: model.controllerProfile.side, pressed: model.pressed,
                              onSelect: { _ in }, generation: model.controllerProfile.generation, showsStickDirections: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 224)
            SettingsPanel("输入反馈", symbol: "hand.tap") {
                LabeledContent(model.controllerTitle) { connectionStatus }
                Divider()
                LabeledContent("当前输入", value: labels(for: model.pressed, fallback: "等待输入"))
                LabeledContent("已收到按键", value: labels(for: setup.testedButtons, fallback: "尚未收到"))
                Text("向导期间，手柄输入仅用于检测。完成或退出向导后即可使用已启用的映射。")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func labels(for inputs: Set<ControllerInput>, fallback: String) -> String {
        if inputs.isEmpty { return fallback }
        return ControllerInput.allCases.filter(inputs.contains).map(\.label).joined(separator: "、")
    }
}
