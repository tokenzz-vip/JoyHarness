import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HarnessesPage: View {
    @ObservedObject var model: DashboardModel
    @State private var removing: HarnessBinding?
    @State private var runningApplications: [NSRunningApplication] = []
    var body: some View {
        VStack(spacing: SettingsStyle.Spacing.groups) {
            SettingsPanel {
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    HarnessIcon(size: 15).foregroundStyle(.secondary)
                    Text("应用 Harness").font(SettingsStyle.Typography.panelTitle)
                    Spacer()
                    Button("添加应用", systemImage: "plus", action: model.addHarness).buttonStyle(.borderedProminent)
                }
                Text("当前手柄：\(model.controllerProfile.name)。应用成为前台时自动使用其绑定方案，同一方案可绑定多个 Harness。")
                    .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                if model.configuration.harnesses.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "app.connected.to.app.below.fill").font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("为应用创建 Harness").font(.headline)
                        Text("浏览器使用导航按键，演示软件使用翻页按键。")
                            .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                        Button("选择一个应用…", action: model.addHarness)
                    }.frame(maxWidth: .infinity).padding(.vertical, 35)
                }
                ForEach($model.configuration.harnesses) { $binding in
                    let url = binding.installedApplicationURL
                    let running = runningApplications.contains { binding.matches(bundleID: $0.bundleIdentifier) }
                    let status = !binding.enabled ? "已停用" : running ? "运行中" : url == nil ? "未安装" : "未运行"
                    Divider()
                    HStack(spacing: SettingsStyle.Spacing.controls) {
                        Group {
                            if let url {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().scaledToFit()
                            } else {
                                Image(systemName: "app.dashed").font(.system(size: 24)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .opacity(binding.enabled ? 1 : 0.45)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(binding.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                Circle().fill(binding.enabled && running ? Color.green : Color.secondary)
                                    .frame(width: 5, height: 5).accessibilityHidden(true)
                                Text(status)
                                if binding.isBuiltIn { Text("· 内置") }
                            }.font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Picker("按键方案", selection: $binding.profileID) {
                            ForEach(model.configuration.profiles) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(width: 190)
                        Button("编辑方案") { model.selectProfile(binding.profileID); model.page = .mapping }.controlSize(.small)
                        Toggle("启用 \(binding.name) Harness", isOn: $binding.enabled)
                            .labelsHidden().toggleStyle(SettingsSwitchStyle()).controlSize(.small)
                        Menu {
                            Button("打开应用") { if let url { NSWorkspace.shared.open(url) } }.disabled(url == nil)
                            if !binding.isBuiltIn {
                                Divider()
                                Button("移除 Harness…", role: .destructive) { removing = binding }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 18) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("\(binding.name) 的更多操作")
                    }.padding(.vertical, 5)
                }
            }
            Label("停用会保留方案绑定；移除 Harness 后，按键方案仍会保留。", systemImage: "info.circle")
                .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: refreshApplications)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshApplications() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshApplications() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshApplications() }
        .confirmationDialog("移除应用 Harness？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { binding in
            Button("移除 Harness", role: .destructive) { model.configuration.harnesses.removeAll { $0.id == binding.id }; removing = nil }
            Button("取消", role: .cancel) { removing = nil }
        } message: { binding in Text("将解除「\(binding.name)」的方案绑定，保留按键方案。") }
    }

    private func refreshApplications() {
        runningApplications = NSWorkspace.shared.runningApplications
    }
}

struct MappingEditor: View {
    @ObservedObject var model: DashboardModel
    let input: ControllerInput
    @State var gesture: Gesture
    @Environment(\.dismiss) private var dismiss
    @State private var scope: Scope
    @State private var actions: [Gesture: ButtonMapping]

    private struct Scope {
        let controllerID: String
        let profileID: UUID
        let globalButtonID: UUID?
        let label: String
        let original: [Gesture: ButtonMapping]
    }

    init(model: DashboardModel, input: ControllerInput, gesture: Gesture) {
        self.model = model; self.input = input; _gesture = State(initialValue: gesture)
        let global = model.globalButton(for: input)
        let label = global == nil ? "按键方案：\(model.selectedProfile.name)" : "全局按键 · 保存的动作对所有方案生效"
        let saved = Dictionary(uniqueKeysWithValues: Gesture.allCases.map {
            ($0, model.mappingForEditing(input, gesture: $0))
        })
        _scope = State(initialValue: Scope(controllerID: model.controllerProfile.id, profileID: model.selectedProfileID,
                                          globalButtonID: global?.id, label: label, original: saved))
        var draft = saved
        if let id = model.macroBindingRequest { draft[gesture] = .init(action: .macro, macroID: id) }
        _actions = State(initialValue: draft)
    }
    private var draft: Binding<ButtonMapping> {
        let trigger = gesture
        return Binding(get: { actions[trigger] ?? .init() }, set: { actions[trigger] = $0 })
    }
    private var scopeMatches: Bool {
        model.voiceInput != input && scope.controllerID == model.controllerProfile.id
            && scope.globalButtonID == model.globalButton(for: input)?.id
            && (scope.globalButtonID != nil || scope.profileID == model.selectedProfileID)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                Image(systemName: input.symbol)
                    .font(.system(size: 22)).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(input.label) · \(gesture.label)").font(SettingsStyle.Typography.dialogTitle)
                    Text(scope.label)
                        .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(SettingsStyle.pagePadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
                    HStack(spacing: SettingsStyle.Spacing.inline) {
                        Text("触发方式").font(SettingsStyle.Typography.body).accessibilityHidden(true)
                        Picker("触发方式", selection: $gesture) { ForEach(Gesture.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden().pickerStyle(.segmented)
                    }
                    ActionFields(mapping: draft, model: model, recordingContext: gesture)
                    if input.isStickDirection {
                        Text("方向动作仅在「方向映射」模式生效。")
                            .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(SettingsStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("清除动作") { actions[gesture] = .init() }
                Spacer()
                if !scopeMatches {
                    Text("手柄或方案已切换，请重新打开编辑。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let changes = actions.filter { scope.original[$0.key] != $0.value }
                    if !changes.isEmpty { model.saveMappings(changes, input: input) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!scopeMatches || !actions.values.allSatisfy(\.isComplete))
            }
            .padding(.horizontal, SettingsStyle.pagePadding).padding(.vertical, SettingsStyle.Spacing.groups)
        }
        .frame(width: 560, height: 420)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { model.beginEditing() }
        .onDisappear { model.endEditing() }
    }
}

extension ButtonMapping {
    var isComplete: Bool {
        switch action {
        case .recordedShortcut: shortcut != nil
        case .openApplication: applicationPath?.isEmpty == false
        case .phrase: text?.isEmpty == false
        case .macro: macroID != nil
        default: true
        }
    }
}

struct ActionFields: View {
    @Binding var mapping: ButtonMapping
    @ObservedObject var model: DashboardModel
    @State private var capturingShortcut = false
    @State private var selectedMacroTagIDs: Set<String> = []
    var recordingContext: Gesture = .single
    var allowMacro = true

    private var availableActions: [RemoteAction] {
        RemoteAction.allCases.filter { action in
            guard action != .voiceShortcut else { return false }
            let legacyModeAction = [.cycleLeftStickMode, .cycleRightStickMode].contains(action)
            let unavailable = [.macro, .toggleMode, .cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode].contains(action)
            return (!legacyModeAction || mapping.action == action) && (allowMacro || !unavailable)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MappingEditorField("执行动作") {
                SettingsSingleSelectionPicker(selection: Binding(get: { mapping.action }, set: { mapping.action = $0 }),
                    options: availableActions.map { SettingsSelectionOption(value: $0, title: $0.label) },
                    accessibilityLabel: "执行动作", identifier: "mapping-action-picker")
            }
            switch mapping.action {
            case .cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode:
                Text("每次触发在鼠标模式和方向映射之间切换。切换后先让摇杆回中，再继续操作。")
                    .font(SettingsStyle.Typography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .openPhrases:
                Text("打开常用语浮层后，用方向键或拨动摇杆选择四个方向，按 A 或按下摇杆选择中央。单击输入内容 1，双击输入内容 2。")
                    .font(SettingsStyle.Typography.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .recordedShortcut:
                ShortcutBindingEditor(shortcut: $mapping.shortcut, capturing: $capturingShortcut)
                    .id(recordingContext)
                    .onDisappear { capturingShortcut = false }
            case .openApplication:
                HStack {
                    Text(mapping.applicationPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "尚未选择应用").font(.system(size: 12))
                    Spacer()
                    Button("选择…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK { mapping.applicationPath = panel.url?.path }
                    }
                }
            case .phrase:
                TextEditor(text: Binding(get: { mapping.text ?? "" }, set: { mapping.text = $0 }))
                    .font(.system(size: 13)).padding(8).frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            case .macro:
                MacroReferencePicker(referenceID: Binding(
                    get: { mapping.macroID?.uuidString },
                    set: { mapping.macroID = $0.flatMap(UUID.init(uuidString:)) }
                ), tagIDs: $selectedMacroTagIDs, model: model)
            default: EmptyView()
            }
        }
    }
}
