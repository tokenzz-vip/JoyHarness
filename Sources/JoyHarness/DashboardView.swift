import AppKit
import CoreBluetooth
import SwiftUI

typealias DashboardStyle = SettingsStyle

private enum Style {
    static let accent = Color.blue
    static let left = Color(red: 0.13, green: 0.65, blue: 0.77)
    static let right = Color(red: 0.94, green: 0.37, blue: 0.30)
    static let background = Color(nsColor: .controlBackgroundColor)
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @State private var statisticsRange = StatisticsRange.lastSevenDays
    @State private var clearStatisticsVisible = false
    @State private var feedbackVisible = false
    @State private var editing: ControllerInput?
    @State private var gesture = Gesture.single
    @State private var actionFilter = MappingActionFilter.all
    @State private var profileName = ""
    @State private var profileNaming: ProfileNaming?

    private enum ProfileNaming: Hashable, Identifiable {
        case new, rename(UUID)

        var id: Self { self }
        var profileID: UUID? {
            if case let .rename(id) = self { return id }
            return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: DashboardStyle.sidebarWidth)
            Color.primary.opacity(0.08).frame(width: 1)
            VStack(spacing: 0) {
                header
                Divider()
                if model.page == .mapping || model.page == .macros || model.page == .phrases {
                    content
                        .padding(DashboardStyle.pagePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if model.page == .mapping { mappingFooter }
                } else {
                    ScrollView {
                        content
                            .padding(DashboardStyle.pagePadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(model.page == .statistics ? .never : .automatic)
                    .id(model.page)
                }
                if let deleted = model.phraseDeletionUndoStack.last {
                    PhraseDeletionUndoBar(model: model, deleted: deleted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Style.background)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: DashboardStyle.minimumWindowSize.width, minHeight: DashboardStyle.minimumWindowSize.height)
        .tint(Style.accent)
        .preferredColorScheme(model.themeMode.colorScheme)
        .confirmationDialog("清除使用统计？", isPresented: $clearStatisticsVisible, titleVisibility: .visible) {
            Button("清除统计", role: .destructive, action: model.clearStatistics)
            Button("取消", role: .cancel) {}
        } message: { Text("将删除所有按键次数记录，且无法恢复。") }
        .sheet(item: $model.pendingPhraseDeletion) { pending in
            PhraseDeletionConfirmationSheet(model: model, pending: pending)
        }
        .sheet(item: $model.pendingConfigurationImport) { preview in
            ConfigurationImportSheet(model: model, preview: preview)
        }
        .sheet(item: $editing) { input in
            if model.voiceInput == input {
                VoiceButtonEditor(model: model, input: input)
            } else {
                MappingEditor(model: model, input: input, gesture: gesture, actionFilter: $actionFilter)
            }
        }
        .sheet(item: $profileNaming) { request in
            let creating = request == .new
            ProfileNameSheet(title: creating ? "新建按键方案" : "重命名按键方案",
                             symbol: creating ? "plus" : "pencil",
                             confirmTitle: creating ? "创建" : "保存", name: $profileName,
                             validateName: {
                                 $0.isEmpty ? nil : model.profileNameError($0, excluding: request.profileID)
                             },
                             onCancel: { profileNaming = nil }, onConfirm: {
                                 if model.saveProfile(name: profileName, replacing: request.profileID) {
                                     profileNaming = nil
                                     if creating { model.page = .mapping }
                                 }
                             })
        }
        .sheet(isPresented: $feedbackVisible) { FeedbackSheet(model: model) }
        .onChange(of: editing) { _, input in
            if input == nil { model.macroBindingRequest = nil }
        }
        .onChange(of: model.macroBindingRequest) { _, id in
            if id != nil {
                actionFilter = .custom
                gesture = .single
                let preferred: ControllerInput = model.controllerProfile.side == .left ? .up : .a
                editing = model.voiceInput == preferred
                    ? model.controllerInputs.first { $0 != model.voiceInput } : preferred
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: SettingsStyle.Spacing.inline) {
                if let issue = model.notices.last(where: { $0.level.autoDismissAfter == nil }) {
                    DashboardNoticeView(notice: issue) { model.dismissNotice(issue.id) }
                }
                if let transient = model.notices.last(where: { $0.level.autoDismissAfter != nil }) {
                    DashboardNoticeView(notice: transient) { model.dismissNotice(transient.id) }
                }
            }
            .padding(.top, SettingsStyle.pageHeaderHeight)
            .padding(.trailing, SettingsStyle.pagePadding)
        }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: BrandAssets.applicationIcon)
                    .resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                Text("JoyHarness").font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12).padding(.bottom, 20)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(DashboardPage.allCases.filter { $0 != .statistics }) { page in nav(page) }
                }
            }
            nav(.statistics).padding(.bottom, 10)
        }
        .frame(maxHeight: .infinity)
        .background(Style.background)
    }
    private func nav(_ page: DashboardPage) -> some View {
        Button {
            model.page = page
        } label: {
            VStack(spacing: 8) {
                Group {
                    if page == .harnesses {
                        HarnessIcon()
                    } else {
                        Image(systemName: page.symbol)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 22, weight: .regular))
                    }
                }.frame(width: 28, height: 28)
                Text(page.shortTitle).font(.system(size: 12, weight: .medium)).frame(height: 16)
            }
            .frame(maxWidth: .infinity).frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.page == page ? Style.accent : Color.primary.opacity(0.76))
        .background(model.page == page ? Style.accent.opacity(0.10) : .clear)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(model.page == page ? .isSelected : [])
    }
    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 28) {
                Text(model.page.title).font(SettingsStyle.Typography.pageTitle)
                if model.page != .statistics {
                    Toggle("启用手柄映射", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                        .toggleStyle(SettingsSwitchStyle()).controlSize(.small).font(SettingsStyle.Typography.body)
                        .help("仅选中的手柄生效；关闭后可从此处或菜单栏恢复。")
                }
            }.fixedSize()
            Spacer(minLength: 8)
            if model.page == .statistics {
                Picker("时间范围", selection: $statisticsRange) {
                    ForEach(StatisticsRange.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 230)
                Button("清除统计") { clearStatisticsVisible = true }.buttonStyle(.bordered).controlSize(.small)
                Label("数据仅存本机", systemImage: "lock").font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
            } else {
                stickModeStatus
                deviceCard
            }
        }
        .padding(.horizontal, SettingsStyle.pagePadding).padding(.vertical, 18)
        .frame(height: SettingsStyle.pageHeaderHeight)
    }
    private var stickModeStatus: some View {
        let side = model.controllerProfile.side
        let mode = model.currentStickMode(for: side)
        return HStack(spacing: 6) {
            Image(systemName: mode.symbol)
            Text("当前手柄 · \(mode.label)")
        }
        .font(SettingsStyle.Typography.caption.weight(.medium))
        .foregroundStyle(mode == .pointer ? Color.accentColor : .secondary)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(mode == .pointer ? Color.accentColor.opacity(0.10) : SettingsStyle.subtle,
                    in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsStyle.controlRadius)
                .strokeBorder(mode == .pointer ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前摇杆模式")
        .accessibilityValue("当前手柄，\(mode.label)")
        .help("当前所选手柄的摇杆模式")
        .fixedSize()
    }
    private var deviceCard: some View {
        ControllerDeviceMenu(model: model) {
            HStack(spacing: SettingsStyle.Spacing.inline) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.controllerTitle).font(SettingsStyle.Typography.body.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle().fill(model.selectedDeviceReady ? .green : .secondary).frame(width: 6, height: 6)
                        Text(model.selectedDeviceReady ? "已连接" : "未连接")
                            .foregroundStyle(model.selectedDeviceReady ? Color.green : Color.secondary)
                        if let device = model.selectedDevice, device.ready, let battery = device.battery,
                           let label = device.batteryLabel {
                            Image(systemName: batterySymbol(for: battery))
                            Text(label)
                        }
                    }.font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(SettingsStyle.Typography.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, SettingsStyle.controlPadding)
            }
            .foregroundStyle(.primary)
            .padding(SettingsStyle.controlPadding)
            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsStyle.controlRadius).strokeBorder(Color.primary.opacity(0.1)) }
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
        }.fixedSize().help("更换手柄；仅选中的手柄生效")
    }
    @ViewBuilder private var content: some View {
        switch model.page {
        case .mapping:
            MappingPage(model: model, editing: editing, onRenameProfile: { renameProfile(model.selectedProfile) }) { input, gesture in
                self.gesture = gesture
                editing = input
            }
        case .harnesses: HarnessesPage(model: model)
        case .profiles:
            ProfilesPage(model: model) {
                profileName = ""
                profileNaming = .new
            } onDuplicate: { id in
                guard model.duplicateProfile(id) != nil else { return }
                model.page = .mapping
                renameProfile(model.selectedProfile)
            }
        case .macros: MacrosPage(model: model)
        case .phrases: PhrasesPage(model: model)
        case .connection: connectionPage
        case .settings: settingsPage
        case .statistics: StatisticsPage(statistics: model.statistics, range: statisticsRange)
        }
    }
    private func renameProfile(_ profile: KeyProfile) {
        profileName = profile.name
        profileNaming = .rename(profile.id)
    }

    private var mappingFooter: some View {
        HStack(spacing: SettingsStyle.Spacing.groups) {
            Label(model.selectedDeviceReady ? "手柄输入已连接" : "等待选中的手柄连接", systemImage: "keyboard")
                .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
            Divider().frame(height: 30)
            Button("连接与摇杆") { model.page = .connection }
            if !model.accessibility {
                Button("授权辅助功能", action: model.requestAccessibility).controlSize(.small)
            }
            Spacer()
            Button("设置全局按键") { model.page = .settings }
            Button("常用语") { model.page = .phrases }
            Button("管理方案") { model.page = .profiles }
        }
        .padding(.horizontal, SettingsStyle.pagePadding).padding(.vertical, SettingsStyle.Spacing.groups)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
    private var connectionPage: some View {
        HStack(alignment: .top, spacing: SettingsStyle.Spacing.groups) {
            SettingsPanel {
                VStack(spacing: 16) {
                    Text(model.controllerProfile.name).font(.system(size: 14, weight: .semibold))
                    Text(model.controllerProfile.generation == .first ? "Bluetooth HID · 一代" : "Bluetooth LE · 二代")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    JoyConArtwork(side: model.controllerProfile.side, pressed: model.pressed,
                                  onSelect: { _ in }, generation: model.controllerProfile.generation)
                        .allowsHitTesting(false).padding(.vertical, 16)
                    ControllerDeviceMenu(model: model) {
                        HStack {
                            Text(model.controllerTitle).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }.font(SettingsStyle.Typography.body).foregroundStyle(.primary)
                            .padding(10).frame(height: 36)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)) }
                    }
                    Text("可连接多个手柄，只有选中的一只生效。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 224)
            VStack(spacing: SettingsStyle.Spacing.groups) {
                SettingsPanel {
                    HStack(spacing: 12) {
                        Label("连接信息", systemImage: "antenna.radiowaves.left.and.right").font(SettingsStyle.Typography.panelTitle)
                        Spacer(minLength: 0)
                        Button("重新扫描", action: model.rescan)
                        Button("打开蓝牙设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                    }.controlSize(.small)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("选中手柄").foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Circle().frame(width: 6, height: 6)
                                Text(model.selectedDeviceReady ? "已连接" : "等待连接")
                            }
                                .foregroundStyle(model.selectedDeviceReady ? Color.green : Color.secondary)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("已连接设备").foregroundStyle(.secondary)
                            Text("\(model.connectedCount) 个")
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("电量").foregroundStyle(.secondary)
                            let device = model.selectedDevice
                            Label(device?.batteryLabel ?? "未知", systemImage: batterySymbol(for: device?.battery ?? 0))
                                .foregroundStyle(.secondary)
                        }
                    }.font(SettingsStyle.Typography.body)
                    Divider()
                    Text(model.hidStatus).font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                    Text(model.bleStatus).font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                SettingsPanel("手柄设备", symbol: "gamecontroller") {
                    let devices = model.connectedDevices
                    if devices.isEmpty {
                        Text("当前没有已连接的手柄。一代可在系统蓝牙中配对，二代可长按 SYNC 后重新扫描。")
                            .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    }
                    ForEach(devices) { device in
                        deviceRow(device)
                        if device.id != devices.last?.id { Divider() }
                    }
                    Text("切换会释放旧手柄的按键。请松开新手柄的按键并让摇杆回中后再操作。断线后保留选择，等待原手柄重连。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                SettingsPanel("鼠标模式设置", symbol: "computermouse") {
                    HStack(spacing: SettingsStyle.Spacing.groups) {
                        mouseButtonPicker(.left)
                        mouseButtonPicker(.right)
                    }
                    Text("鼠标按键仅在鼠标模式下生效。可选择当前手柄的非全局实体按键，摇杆按下除外。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("摇杆死区").frame(width: 64, alignment: .leading)
                        Slider(value: $model.configuration.deadzone, in: 0.05...0.6).accessibilityLabel("摇杆死区")
                        Text(model.configuration.deadzone, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 40)
                    }
                    HStack {
                        Text("指针速度").frame(width: 64, alignment: .leading)
                        Slider(value: $model.configuration.pointerSpeed, in: 1...40).accessibilityLabel("指针速度")
                        Text(model.configuration.pointerSpeed, format: .number.precision(.fractionLength(0))).monospacedDigit().frame(width: 40)
                    }
                    HStack {
                        Text("先松开摇杆，再校准中心。").foregroundStyle(.secondary)
                        Spacer()
                        Button("校准中心") { if let device = model.selectedDevice { model.calibrate(device) } }
                            .disabled(!model.selectedDeviceReady)
                    }
                }.font(SettingsStyle.Typography.body)
            }
        }
    }
    private func deviceRow(_ device: ConnectedJoyCon) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 5) {
                Text(device.profile.name).font(SettingsStyle.Typography.body.weight(.semibold))
                Text(device.identitySuffix + " · " + device.status)
                    .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if model.controllerSelection.deviceID == device.id {
                SettingsStatus(title: "已选中", color: .accentColor)
            } else {
                Button("使用此手柄") { model.selectDevice(device.id) }.controlSize(.small)
            }
        }
    }
    private func mouseButtonPicker(_ role: MouseButtonRole) -> some View {
        HStack {
            Text(role.label).frame(width: 64, alignment: .leading)
            Picker(role.label, selection: Binding<ControllerInput?>(
                get: {
                    role == .left ? model.mouseButtonBindings.left : model.mouseButtonBindings.right
                },
                set: { model.setMouseButton($0, for: role) }
            )) {
                Text("未设置").tag(nil as ControllerInput?)
                ForEach(model.mouseButtonChoices(for: role)) { input in
                    Text(input.label).tag(Optional(input))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity)
    }
    private var settingsPage: some View {
        VStack(spacing: SettingsStyle.Spacing.groups) {
            SettingsPanel {
                HStack(alignment: .top, spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(nsImage: BrandAssets.applicationIcon).resizable().scaledToFit().frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JoyHarness").font(.system(size: 20, weight: .semibold))
                            Text("用 Joy-Con 操作应用、快捷键和鼠标，让手柄融入日常工作流。")
                                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                            Text("支持 Joy-Con 一代、二代 · 仅选中的手柄生效")
                                .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                            HStack(spacing: SettingsStyle.Spacing.groups) {
                                Link("项目主页", destination: AppInfo.repository)
                                Link("项目官网", destination: AppInfo.website)
                            }
                            .font(SettingsStyle.Typography.body)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("当前版本").foregroundStyle(.secondary)
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0")
                                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                        }.font(SettingsStyle.Typography.body)
                        Text("Intel 或 Apple Silicon · macOS 14 及以上").font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                        AppUpdateSettingsView(model: model.updates)
                    }.frame(width: 300, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: true)
            }
            GlobalButtonsPanel(model: model)
            SettingsPanel("权限", symbol: "shield.lefthalf.filled") {
                permissionRow("蓝牙", detail: "发现并连接 Joy-Con 2", symbol: "antenna.radiowaves.left.and.right",
                              granted: CBManager.authorization == .allowedAlways) { model.openPrivacy("Privacy_Bluetooth") }
                Divider()
                permissionRow("输入监控", detail: "接收一代 Joy-Con 的 HID 按键", symbol: "keyboard",
                              granted: model.inputMonitoring, action: model.requestInputMonitoring)
                Divider()
                permissionRow("辅助功能", detail: "向当前应用发送键盘与鼠标操作", symbol: "hand.raised",
                              granted: model.accessibility, action: model.requestAccessibility)
            }
            SettingsPanel("通用", symbol: "gearshape") {
                SettingsPreference(symbol: "arrow.up.arrow.down", title: "配置导入与导出", detail: "备份全局按键、键位方案、Harness、组合动作、常用语和摇杆设置。") {
                    HStack {
                        Button("导出配置", action: model.exportConfiguration)
                        Button("导入配置", action: model.importConfiguration)
                        Button("恢复替换前配置", action: model.previewConfigurationRecovery)
                            .disabled(model.configurationRecoveryDate == nil)
                            .help(model.configurationRecoveryDate.map {
                                "预览 \($0.formatted(date: .abbreviated, time: .shortened)) 保存的配置"
                            } ?? "首次替换配置后可恢复")
                    }
                }
                Divider()
                SettingsPreference(symbol: "power", title: "启动行为", detail: "选择登录和打开应用时的行为。") {
                    HStack(spacing: 16) {
                        Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        Toggle("启动时打开主面板", isOn: $model.openAtLaunch)
                    }.toggleStyle(SettingsSwitchStyle()).controlSize(.small).font(SettingsStyle.Typography.caption)
                }
                Divider()
                SettingsPreference(symbol: "dock.rectangle", title: "在 Dock 中显示应用图标", detail: "隐藏后仍可从菜单栏打开设置。") {
                    Toggle("显示 Dock 图标", isOn: $model.showDockIcon).labelsHidden().toggleStyle(SettingsSwitchStyle())
                }
                Divider()
                SettingsPreference(symbol: "globe", title: "应用语言", detail: "当前界面使用简体中文。") {
                    Text("简体中文").font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                }
                Divider()
                SettingsPreference(symbol: "circle.lefthalf.filled", title: "主题模式", detail: "选择应用外观，切换后立即生效。") {
                    Picker("主题模式", selection: $model.themeMode) {
                        ForEach(AppThemeMode.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
                Divider()
                SettingsPreference(symbol: "gamecontroller", title: "连接手柄", detail: "一代在系统蓝牙中配对；二代长按 SYNC 后扫描。") {
                    Button("查看连接设置") { model.page = .connection }
                }
            }
            SettingsPanel("诊断与支持", symbol: "stethoscope") {
                HStack {
                    Text("复制权限和连接状态，帮助排查问题。").font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    Spacer()
                    Button("复制诊断信息", action: model.copyDiagnostics)
                    Button("刷新状态", action: model.refreshPermissions)
                    Button("提交反馈") { feedbackVisible = true }
                }
            }
        }
    }
    private func permissionRow(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        SettingsPreference(symbol: symbol, title: title, detail: detail) {
            HStack(spacing: 12) {
                SettingsStatus(title: granted ? "已授权" : "待授权", color: granted ? .green : .orange)
                Button(granted ? "系统设置" : "前往授权", action: action).frame(width: 84)
            }
        }
    }
}

private struct AppUpdateSettingsView: View {
    @ObservedObject var model: AppUpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("检查更新…", action: model.checkForUpdates)
                    .disabled(!model.canCheckForUpdates)
                Button("版本历史") {
                    NSWorkspace.shared.open(AppInfo.repository.appending(path: "releases"))
                }
            }
            .controlSize(.small)
            .font(SettingsStyle.Typography.caption)
            HStack(spacing: 8) {
                Toggle("自动检查更新", isOn: Binding(
                    get: { model.automaticallyChecksForUpdates },
                    set: model.setAutomaticallyChecksForUpdates
                ))
                .toggleStyle(.checkbox)
                .disabled(!model.isConfigured)
                .fixedSize()
                Text(model.lastUpdateCheckDate.map {
                    "上次检查：\($0.formatted(date: .abbreviated, time: .shortened))"
                } ?? "尚未检查更新")
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            .font(SettingsStyle.Typography.caption)
        }
    }
}

/// Original vector artwork keeps both generations legible without downloaded images.
struct JoyConArtwork: View {
    static let faceWidth: CGFloat = 130

    let side: JoyConSide
    let pressed: Set<ControllerInput>
    let onSelect: (ControllerInput) -> Void
    var onHover: ((ControllerInput?) -> Void)? = nil
    var generation: JoyConGeneration = .first
    var showsStickDirections = false
    private var accent: Color { side == .left ? Style.left : Style.right }
    private var isSecondGeneration: Bool { generation == .second }
    var body: some View {
        VStack(spacing: SettingsStyle.Spacing.controls) {
            controllerFace
                .shadow(color: .black.opacity(0.12), radius: 10, x: 3, y: 6)
            Text("JOY-CON\(generation == .second ? " 2" : "")  ·  \(side == .left ? "L" : "R")")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
        }
    }
    // The existing shell provides a common coordinate space for both generations.
    private var controllerFace: some View {
        GeometryReader { _ in
            ZStack {
                RoundedRectangle(cornerRadius: 40).fill(accent.gradient)
                RoundedRectangle(cornerRadius: 40).strokeBorder(.white.opacity(0.3), lineWidth: 1)
                if side == .left { leftFace } else { rightFace }
            }
        }
        .frame(width: Self.faceWidth, height: 321)
    }
    private var leftFace: some View {
        ZStack {
            key(.minus, size: 20).position(x: isSecondGeneration ? 101 : 104, y: isSecondGeneration ? 38 : 41)
            shoulder(.l, x: 45, y: 6)
            shoulder(.zl, x: 88, y: 6)
            stick(.leftStick).position(x: 57, y: upperControlsY)
            buttonCluster(.up, .left, .right, .down)
                .position(x: 57, y: lowerControlsY)
            key(.capture, size: 19).position(x: 85, y: captureAndHomeY)
            rail(.leftSL, y: upperRailY)
            rail(.leftSR, y: lowerRailY)
        }
    }
    private var rightFace: some View {
        ZStack {
            key(.plus, size: 20).position(x: isSecondGeneration ? 29 : 26, y: isSecondGeneration ? 38 : 41)
            shoulder(.zr, x: 42, y: 6)
            shoulder(.r, x: 85, y: 6)
            buttonCluster(.x, .y, .a, .b)
                .position(x: 73, y: upperControlsY)
            stick(.rightStick).position(x: 73, y: lowerControlsY)
            key(.home, size: 22).position(x: 45, y: captureAndHomeY)
            rail(.rightSR, y: upperRailY)
            rail(.rightSL, y: lowerRailY)
            if isSecondGeneration { key(.c, size: 19).position(x: 45, y: captureAndHomeY + 34) }
        }
    }

    private var upperControlsY: CGFloat { isSecondGeneration ? 84 : 87 }
    private var lowerControlsY: CGFloat { isSecondGeneration ? 181 : 179 }
    private let captureAndHomeY: CGFloat = 248
    private var upperRailY: CGFloat { isSecondGeneration ? 88 : 96 }
    private var lowerRailY: CGFloat { isSecondGeneration ? 229 : 226 }

    private func buttonCluster(_ top: ControllerInput, _ left: ControllerInput,
                               _ right: ControllerInput, _ bottom: ControllerInput) -> some View {
        let size: CGFloat = isSecondGeneration ? 24 : 22
        let step: CGFloat = isSecondGeneration ? 25 : 24
        return ZStack {
            key(top, size: size).offset(y: -step)
            key(left, size: size).offset(x: -step)
            key(right, size: size).offset(x: step)
            key(bottom, size: size).offset(y: step)
        }
        .frame(width: size + step * 2, height: size + step * 2)
    }
    private func stick(_ input: ControllerInput) -> some View {
        let diameter: CGFloat = isSecondGeneration ? 55 : 50
        let directionOffset = diameter / 2 + 9
        return ZStack {
            Button { onSelect(input) } label: {
                Circle().fill(pressed.contains(input) ? .white : Color(white: 0.16))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 3).padding(5))
                    .frame(width: diameter, height: diameter).shadow(color: .black.opacity(0.22), radius: 2, y: 2)
            }.buttonStyle(.plain).accessibilityLabel(input.label)
                .onHover { onHover?($0 ? input : nil) }
                .anchorPreference(key: JoyConControlBounds.self, value: .bounds) { [input: $0] }
            if showsStickDirections {
                let directions = ControllerInput.stickDirections(for: side)
                stickDirection(directions[0], symbol: "chevron.up", x: 0, y: -directionOffset)
                stickDirection(directions[1], symbol: "chevron.down", x: 0, y: directionOffset)
                stickDirection(directions[2], symbol: "chevron.left", x: -directionOffset, y: 0)
                stickDirection(directions[3], symbol: "chevron.right", x: directionOffset, y: 0)
            }
        }.frame(width: diameter, height: diameter)
    }
    private func stickDirection(_ input: ControllerInput, symbol: String, x: CGFloat, y: CGFloat) -> some View {
        Button { onSelect(input) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundStyle(pressed.contains(input) ? accent : .white)
                .frame(width: 16, height: 16)
                .background(pressed.contains(input) ? .white : Color(white: 0.16), in: Circle())
        }.buttonStyle(.plain).offset(x: x, y: y)
            .accessibilityLabel(input.label).help("编辑\(input.label)")
            .onHover { onHover?($0 ? input : nil) }
    }
    private func shoulder(_ input: ControllerInput, x: CGFloat, y: CGFloat) -> some View {
        Button { onSelect(input) } label: {
            Text(input.label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(pressed.contains(input) ? accent : .white)
                .frame(width: 31, height: 21)
                .background {
                    if pressed.contains(input) {
                        RoundedRectangle(cornerRadius: 8).fill(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(
                            LinearGradient(colors: [Color(white: 0.25), Color(white: 0.13)], startPoint: .top, endPoint: .bottom)
                        )
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16), lineWidth: 1) }
                .shadow(color: .black.opacity(0.26), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(input.label)
        .onHover { onHover?($0 ? input : nil) }
        .anchorPreference(key: JoyConControlBounds.self, value: .bounds) { [input: $0] }
        .position(x: x, y: y)
    }
    private func rail(_ input: ControllerInput, y: CGFloat) -> some View {
        Button { onSelect(input) } label: {
            ZStack {
                if pressed.contains(input) {
                    Capsule().fill(.white)
                } else {
                    Capsule().fill(
                        LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .leading, endPoint: .trailing)
                    )
                }
                Text(input == .leftSL || input == .rightSL ? "SL" : "SR")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(pressed.contains(input) ? accent : .white)
                    .rotationEffect(.degrees(side == .left ? 90 : -90))
            }
            .frame(width: isSecondGeneration ? 18 : 16, height: isSecondGeneration ? 49 : 34)
            .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1) }
            .shadow(color: .black.opacity(0.26), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(input.label)
        .onHover { onHover?($0 ? input : nil) }
        .anchorPreference(key: JoyConControlBounds.self, value: .bounds) { [input: $0] }
        .position(x: side == .left ? Self.faceWidth - 5 : 5, y: y)
        .zIndex(2)
    }
    private func key(_ input: ControllerInput, size: CGFloat) -> some View {
        let isPressed = pressed.contains(input)
        let fill = isPressed ? Color.white : Color(white: 0.17)
        return Button { onSelect(input) } label: {
            Group {
                switch input {
                case .minus, .plus:
                    Image(systemName: input == .minus ? "minus" : "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(fill)
                case .capture, .c:
                    Text(input == .capture ? "○" : "C")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: size, height: size)
                        .background(fill, in: RoundedRectangle(cornerRadius: 4))
                case .home:
                    Image(systemName: "house.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: size, height: size)
                        .background(fill, in: Circle())
                default:
                    Text(input.label)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: size, height: size)
                        .background(fill, in: Circle())
                }
            }
            .foregroundStyle(isPressed ? accent : .white)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.16), radius: 1, y: 2)
        }.buttonStyle(.plain).accessibilityLabel(input.label)
            .onHover { onHover?($0 ? input : nil) }
            .anchorPreference(key: JoyConControlBounds.self, value: .bounds) { [input: $0] }
    }
}
