import AppKit
import ApplicationServices
import Combine
import CoreBluetooth
import IOKit.hid
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsKeys {
    static let configuration = "configuration.v1"
    static let statistics = "statistics.v1"
    static let controller = "controller.v1"
}

enum DashboardPage: String, CaseIterable, Identifiable {
    case mapping, harnesses, profiles, macros, phrases, connection, settings, statistics
    var id: String { rawValue }
    var title: String {
        switch self { case .mapping: "按键映射"; case .harnesses: "Harness"; case .profiles: "键位方案"
        case .macros: "组合动作"; case .phrases: "常用语"; case .connection: "连接与摇杆"; case .settings: "设置"; case .statistics: "使用统计" }
    }
    var shortTitle: String {
        switch self {
        case .mapping: "按键"; case .harnesses: "Harness"; case .profiles: "键位方案"
        case .macros: "组合动作"; case .phrases: "常用语"; case .connection: "连接"; case .settings: "设置"; case .statistics: "统计"
        }
    }
    var symbol: String {
        switch self { case .mapping: "keyboard"; case .harnesses: "square.grid.2x2"; case .profiles: "rectangle.3.group"
        case .macros: "square.3.layers.3d"; case .phrases: "text.bubble"; case .connection: "link"; case .settings: "gearshape"; case .statistics: "chart.bar.fill" }
    }
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var page = DashboardPage.mapping
    let updates = AppUpdateModel()
    @Published private var storedConfiguration: StoredConfiguration
    @Published var pendingConfigurationImport: ConfigurationImportPreview? {
        willSet {
            if (pendingConfigurationImport == nil) != (newValue == nil), let id = controllerSelection.deviceID {
                engine.disconnect(id)
            }
        }
    }
    var configuration: Configuration {
        get { storedConfiguration.configuration }
        set { saveConfiguration(newValue) }
    }
    var configurationRecoveryDate: Date? { storedConfiguration.recovery?.date }
    @Published var statistics: UsageStatistics
    @Published var selectedProfileID: UUID {
        didSet { defaults.set(selectedProfileID.uuidString, forKey: "JoyHarness.editingProfile") }
    }
    @Published private(set) var controllerSelection: ControllerSelection
    @Published var devices: [ConnectedJoyCon] = []
    @Published var pressed: Set<ControllerInput> = []
    @Published var snapshots: [String: JoyConSnapshot] = [:]
    @Published var enabled = true
    @Published private(set) var notices: [DashboardNotice] = []
    private var noticeTimer: Task<Void, Never>?
    @Published var hidStatus = "一代：尚未启动"
    @Published var bleStatus = "二代：尚未启动"
    @Published var frontmostApp = ""
    @Published var accessibility = false
    @Published var inputMonitoring = false
    @Published private(set) var recordingShortcut = false
    private var editingCount = 0
    /// Publishes stick-mode changes separately from the dashboard notice.
    /// Views that show the current mode and the menu-bar coordinator both depend
    /// on this state changing immediately after a mode cycle.
    @Published private(set) var stickModeRevision = 0
    @Published var pendingPhraseDeletion: PendingPhraseDeletion? {
        didSet {
            if let previous = oldValue?.phraseID, previous != pendingPhraseDeletion?.phraseID {
                clearNotice(for: .phraseDeletion(previous))
            }
        }
    }
    @Published var phraseDeletionUndoStack: [DeletedPhrase] = [] {
        didSet {
            for deleted in oldValue where !phraseDeletionUndoStack.contains(where: { $0.id == deleted.id }) {
                clearNotice(for: .phraseUndo(deleted.id))
            }
        }
    }
    @Published var macroBindingRequest: UUID?
    @Published var themeMode: AppThemeMode { didSet { defaults.set(themeMode.rawValue, forKey: "JoyHarness.theme") } }
    @Published var openAtLaunch: Bool { didSet { defaults.set(openAtLaunch, forKey: "JoyHarness.openAtLaunch") } }
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: "JoyHarness.showDockIcon")
            if !preview { NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory) }
        }
    }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    private let now: () -> TimeInterval
    private var lastReportTimes: [String: TimeInterval] = [:]
    private let defaults: UserDefaults
    private let engine: InputEngine
    private let sender: SystemEventSender
    private let macros = MacroExecutor()
    private let harnessComposerFocus = HarnessComposerFocus()
    private var phrasePicker: PhrasePickerController? = nil
    private let transports: [ControllerTransport]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var activeProfileID: UUID?
    private var statsDirty = false
    private var postedHolds: [ButtonMapping: Int] = [:]
    private var tickCount = 0
    private var started = false
    private var harnessFocusRequest = UUID()
    private let preview: Bool
    var onMenuChange: (() -> Void)?

    init(defaults: UserDefaults = .standard, preview: Bool = false,
         transports: [ControllerTransport]? = nil, inputEngine: InputEngine? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults; self.preview = preview
        self.now = now
        themeMode = AppThemeMode(rawValue: defaults.string(forKey: "JoyHarness.theme") ?? "") ?? .system
        openAtLaunch = defaults.object(forKey: "JoyHarness.openAtLaunch") as? Bool ?? true
        showDockIcon = defaults.object(forKey: "JoyHarness.showDockIcon") as? Bool ?? true
        controllerSelection = SettingsStorage.load(ControllerSelection.self, SettingsKeys.controller, defaults: defaults) ?? .init()
        let stored = SettingsStorage.load(StoredConfiguration.self, SettingsKeys.configuration, defaults: defaults)
        let loaded = stored?.configuration
        let valid = loaded.flatMap { try? $0.validated() }
        if loaded != nil && valid == nil, let data = defaults.data(forKey: "JoyHarness." + SettingsKeys.configuration) {
            defaults.set(data, forKey: "JoyHarness.recovery." + SettingsKeys.configuration)
        }
        let config = (valid ?? Configuration()).addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses()
            .addingBuiltInPhrases()
        let savedFields = defaults.data(forKey: "JoyHarness." + SettingsKeys.configuration).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        let initialConfiguration = StoredConfiguration(configuration: config, recovery: stored?.recovery)
        storedConfiguration = initialConfiguration
        if config != valid || savedFields?["globalGestureOverrides"] as? Bool != true || savedFields?["voiceButtons"] == nil {
            SettingsStorage.save(initialConfiguration, SettingsKeys.configuration, defaults: defaults)
        }
        let editingID = defaults.string(forKey: "JoyHarness.editingProfile").flatMap(UUID.init(uuidString:))
        selectedProfileID = config.profiles.first { $0.id == editingID }?.id ?? config.defaultProfileID ?? config.profiles[0].id
        statistics = SettingsStorage.load(UsageStatistics.self, SettingsKeys.statistics, defaults: defaults) ?? .init()
        engine = inputEngine ?? InputEngine(now: now); sender = SystemEventSender()
        self.transports = transports ?? (preview ? [] : [JoyConHID(), JoyCon2Bluetooth()])
        engine.selectDevice(controllerSelection.deviceID)
        engine.output = { [weak self] in self?.perform($0, pressed: $1) }
        engine.onStickModeChange = { [weak self] side, mode in
            guard let self else { return }
            self.stickModeRevision &+= 1
            self.showNotice(.information, "当前手柄已切换为「\(mode.label)」。")
            self.onMenuChange?()
        }
        macros.output = { [weak self] in self?.perform($0, pressed: $1) }
        phrasePicker = PhrasePickerController(onDismiss: { [weak self] in
            self?.engine.setInputCaptured(false)
        }) { [weak self] text in
            guard let self, self.canSend else { return }
            self.sender.typeText(text)
        }
        engine.pointer = { [weak self] x, y in
            guard let self, self.canSend, let current = CGEvent(source: nil)?.location else { return }
            // Bound the cursor to the screen containing its destination, including
            // displays with negative origins; use a CG mouseMoved event for apps.
            let proposed = CGPoint(x: current.x + x, y: current.y + y)
            var display: CGDirectDisplayID = 0; var count: UInt32 = 0
            guard CGGetDisplaysWithPoint(proposed, 1, &display, &count) == .success else { return }
            let target: CGPoint
            if count > 0 { target = proposed }
            else {
                guard CGGetDisplaysWithPoint(current, 1, &display, &count) == .success, count > 0 else { return }
                let bounds = CGDisplayBounds(display)
                target = CGPoint(x: min(max(proposed.x, bounds.minX), bounds.maxX - 1),
                                 y: min(max(proposed.y, bounds.minY), bounds.maxY - 1))
            }
            self.sender.pointer(from: current, to: target)
        }
        engine.onStale = { [weak self] id in
            guard let self else { return }
            self.phrasePicker?.model.dismiss()
            self.markDeviceStale(id)
            self.refreshPressed()
            self.macros.cancel(); self.onMenuChange?()
        }
        engine.buttonPressed = { [weak self] input in
            guard let self else { return }; self.statistics.record(input); self.statsDirty = true
        }
        for transport in self.transports {
            transport.onDevice = { [weak self] in self?.updateDevice($0) }
            transport.onInput = { [weak self] in self?.receiveInput(id: $0, profile: $1, snapshot: $2) }
            transport.onDisconnect = { [weak self] in self?.disconnectDevice($0) }
        }
        self.transports.first?.onStatus = { [weak self] in self?.hidStatus = $0 }
        self.transports.last?.onStatus = { [weak self] in self?.bleStatus = $0 }
        applyProfile()
        if preview && transports == nil {
            devices = JoyConProfile.all.map {
                .init(id: $0.id, profile: $0, status: "演示设备", ready: true,
                      battery: $0.generation == .first ? 34 : 75)
            }
            controllerSelection.select(devices[2])
            engine.selectDevice(devices[2].id)
            pressed = [.l]
            hidStatus = "一代：截图预览，未启动设备监听"
            bleStatus = "二代：截图预览，未启动设备监听"
        }
    }
    var selectedDevice: ConnectedJoyCon? { devices.first { $0.id == controllerSelection.deviceID } }
    var controllerProfile: JoyConProfile { controllerSelection.profile ?? JoyConProfile.all[0] }
    var controllerTitle: String {
        guard controllerSelection.profileID != nil else { return "选择手柄" }
        let name = controllerProfile.name
        guard let device = selectedDevice, device.ready else { return name }
        if devices.filter({ $0.profile == device.profile && $0.ready }).count > 1 {
            return name + " · " + device.identitySuffix
        }
        return name
    }
    var selectedDeviceReady: Bool { selectedDevice?.ready == true }
    var controllerInputs: [ControllerInput] { controllerProfile.physicalInputs }
    var globalButtons: [GlobalButton] { configuration.globalButtons[controllerProfile.id] ?? [] }
    var voiceButton: VoiceButton { configuration.voiceButtons[controllerProfile.id] ?? .init(input: nil) }
    var voiceInput: ControllerInput? { voiceButton.input }
    var voiceInputChoices: [ControllerInput] { configuration.voiceInputChoices(for: controllerProfile) }
    var mouseButtonBindings: MouseButtonBindings { configuration.mouseButtons[controllerProfile.id] ?? .init() }
    func mouseButtonChoices(for role: MouseButtonRole) -> [ControllerInput] {
        let global = Set(globalButtons.compactMap(\.input))
        let other = role == .left ? mouseButtonBindings.right : mouseButtonBindings.left
        return controllerInputs.filter { input in
            !input.isStickButton && !input.isStickDirection && !global.contains(input) && input != voiceInput && input != other
        }
    }
    func selectDevice(_ id: String) {
        guard let device = devices.first(where: { $0.id == id && $0.ready }), controllerSelection.deviceID != id else { return }
        controllerSelection.select(device)
        applyControllerSelection()
    }
    func selectControllerProfile(_ profile: JoyConProfile) {
        expireStaleReports()
        controllerSelection.selectProfile(profile)
        if let first = devices.first(where: { $0.profile == profile && $0.ready }) { controllerSelection.select(first) }
        applyControllerSelection()
    }
    private func applyControllerSelection() {
        phrasePicker?.model.dismiss()
        macros.cancel()
        expireStaleReports()
        let baseline = controllerSelection.deviceID.flatMap { snapshots[$0] }
        engine.selectDevice(controllerSelection.deviceID, baseline: baseline)
        applyProfile()
        engine.refreshPausedMapping()
        SettingsStorage.save(controllerSelection, SettingsKeys.controller, defaults: defaults)
        refreshPressed()
        onMenuChange?()
    }
    private func refreshPressed() {
        guard let id = controllerSelection.deviceID, let snapshot = snapshots[id] else { pressed = []; return }
        let next = snapshot.buttons.union(snapshot.stick.directions(side: controllerProfile.side, center: configuration.centers[id],
                                                                   deadzone: configuration.deadzone, previous: pressed))
        if pressed != next { pressed = next }
    }
    private func updateDevice(_ device: ConnectedJoyCon) {
        let previous = devices.first { $0.id == device.id }
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            if devices[index] != device { devices[index] = device }
        } else { devices.append(device) }
        if device.ready, let previousID = device.previousID, controllerSelection.deviceID == previousID {
            controllerSelection.select(device)
            if configuration.centers[device.id] == nil, let center = configuration.centers[previousID] {
                configuration.centers[device.id] = center
            }
            applyControllerSelection()
        } else if controllerSelection.discover(device) {
            applyControllerSelection()
        }
        if previous?.ready != device.ready { onMenuChange?() }
    }
    private func receiveInput(id: String, profile: JoyConProfile, snapshot: JoyConSnapshot) {
        lastReportTimes[id] = now()
        if snapshots[id] != snapshot { snapshots[id] = snapshot }
        // Non-selected input remains available for device diagnostics and calibration.
        guard id == controllerSelection.deviceID else { return }
        if pendingConfigurationImport != nil { refreshPressed(); return }
        if !recordingShortcut {
            let pickerWasPresented = phrasePicker?.model.isPresented == true
            // Record the modal report before it can dismiss the picker, so held inputs stay suppressed.
            engine.receive(id: id, profile: profile, snapshot: snapshot)
            if pickerWasPresented {
                phrasePicker?.model.receive(snapshot, center: configuration.centers[id], deadzone: configuration.deadzone)
            }
        }
        refreshPressed()
    }
    private func expireStaleReports() {
        let time = now()
        let staleIDs = lastReportTimes.compactMap { id, last in time - last >= InputEngine.reportTimeout ? id : nil }
        for id in staleIDs { markDeviceStale(id) }
        if !staleIDs.isEmpty {
            refreshPressed()
            onMenuChange?()
        }
    }

    private func markDeviceStale(_ id: String) {
        lastReportTimes[id] = nil
        snapshots[id] = nil
        if let index = devices.firstIndex(where: { $0.id == id }) {
            Log.app.notice("Controller input report timeout: \(self.devices[index].profile.id, privacy: .public)")
            devices[index].ready = false
            devices[index].status = "输入已中断，请唤醒手柄或重新扫描。"
        }
    }

    private func disconnectDevice(_ id: String) {
        lastReportTimes[id] = nil
        engine.disconnect(id)
        snapshots[id] = nil
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index].ready = false
            devices[index].status = "已断开"
        }
        if id == controllerSelection.deviceID {
            phrasePicker?.model.dismiss()
            macros.cancel()
            refreshPressed()
        }
        onMenuChange?()
    }
    var selectedProfile: KeyProfile { configuration.profiles.first { $0.id == selectedProfileID } ?? configuration.profiles[0] }
    var activeProfile: KeyProfile { configuration.profiles.first { $0.id == activeProfileID } ?? selectedProfile }
    var defaultProfile: KeyProfile { configuration.profiles.first { $0.id == configuration.defaultProfileID } ?? configuration.profiles[0] }
    var canAddProfile: Bool { configuration.profiles.filter { !DefaultKeyProfiles.presetIDs.contains($0.id) }.count < 100 }
    func mappingSummary(_ mapping: ButtonMapping) -> String {
        guard mapping.action == .macro,
              let macro = configuration.macros.first(where: { $0.id == mapping.macroID }) else { return mapping.summary }
        return DefaultMacros.cardTitle(for: macro)
    }
    var connectedDevices: [ConnectedJoyCon] { devices.filter(\.ready) }
    var connectedCount: Int { connectedDevices.count }
    private var canSend: Bool { !preview && accessibility && !recordingShortcut && pendingConfigurationImport == nil }

    func start() {
        guard !started, !preview else { return }; started = true
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        refreshPermissions(); transports.forEach { $0.start() }; updates.start()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyProfile() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }; self.engine.tick(); self.tickCount += 1
                if self.tickCount % 30 == 0 { self.expireStaleReports() }
                if self.tickCount % 120 == 0 { self.refreshPermissions(); self.flushStatistics() }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func stop() {
        suspend(); timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observers.removeAll()
        flushStatistics(); started = false
    }
    private func suspend() {
        phrasePicker?.model.dismiss()
        harnessComposerFocus.cancel()
        engine.cancel()
        macros.cancel()
        transports.forEach { $0.stop() }
    }
    func rescan() { guard !preview else { return }; suspend(); transports.forEach { $0.start() } }
    func beginEditing() {
        editingCount += 1
        guard editingCount == 1 else { return }
        phrasePicker?.model.dismiss()
        if let id = controllerSelection.deviceID { engine.disconnect(id) }
        macros.cancel()
        recordingShortcut = true
    }
    func endEditing() {
        guard editingCount > 0 else { return }
        editingCount -= 1
        guard editingCount == 0 else { return }
        if let id = controllerSelection.deviceID { engine.disconnect(id) }
        recordingShortcut = false
    }
    func toggleMapping() { setEnabled(!enabled) }
    func setEnabled(_ value: Bool) {
        if !value { phrasePicker?.model.dismiss() }
        harnessComposerFocus.cancel()
        macros.cancel()
        engine.setEnabled(value)
        enabled = value
        onMenuChange?()
    }
    func selectProfile(_ id: UUID) {
        guard configuration.profiles.contains(where: { $0.id == id }) else { return }
        engine.cancel(); macros.cancel()
        selectedProfileID = id
    }
    func setDefaultProfile(_ id: UUID) {
        guard configuration.profiles.contains(where: { $0.id == id }) else { return }
        configuration.defaultProfileID = id
    }
    func editProfile(_ change: (inout KeyProfile) -> Void) {
        guard let index = configuration.profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        change(&configuration.profiles[index])
    }
    func currentStickMode(for side: JoyConSide) -> StickMode { engine.stickMode(for: side) }
    func globalButton(for input: ControllerInput) -> GlobalButton? {
        globalButtons.first { $0.input == input }
    }
    func mappingForEditing(_ input: ControllerInput, gesture: Gesture) -> ButtonMapping {
        globalButton(for: input)?.actions[gesture] ?? selectedProfile.mapping[input, gesture]
    }
    func globalInputChoices(for id: UUID) -> [ControllerInput] {
        let assigned = Set(globalButtons.filter { $0.id != id }.compactMap(\.input))
        return controllerInputs.filter { !assigned.contains($0) && $0 != voiceInput }
    }
    func setVoiceInput(_ input: ControllerInput?) {
        guard input != voiceInput, input.map(voiceInputChoices.contains) ?? true else { return }
        var button = voiceButton
        button.input = input
        configuration.voiceButtons[controllerProfile.id] = button
    }
    func saveVoiceButton(_ button: VoiceButton, controllerID: String) -> Bool {
        guard controllerProfile.id == controllerID, let input = button.input, input == voiceInput,
              (1...2).contains(button.tapKeys.count) else { return false }
        var next = configuration
        next.voiceButtons[controllerID] = button
        return saveConfiguration(next)
    }
    func setGlobalInput(_ input: ControllerInput?, for id: UUID) {
        var buttons = globalButtons
        guard let index = buttons.firstIndex(where: { $0.id == id }),
              buttons[index].input != input,
              input.map({ globalInputChoices(for: id).contains($0) }) ?? (index > 0) else { return }
        buttons[index].input = input
        var next = configuration
        next.globalButtons[controllerProfile.id] = buttons
        if let input {
            var mouse = mouseButtonBindings
            if mouse.left == input { mouse.left = nil }
            if mouse.right == input { mouse.right = nil }
            next.mouseButtons[controllerProfile.id] = mouse
        }
        configuration = next
    }
    func setMouseButton(_ input: ControllerInput?, for role: MouseButtonRole) {
        let choices = mouseButtonChoices(for: role)
        guard input == nil || choices.contains(input!) else { return }
        var bindings = mouseButtonBindings
        if role == .left { bindings.left = input } else { bindings.right = input }
        configuration.mouseButtons[controllerProfile.id] = bindings
    }
    func addGlobalButton() {
        configuration.globalButtons[controllerProfile.id]?.append(GlobalButton())
    }
    func removeGlobalButton(_ id: UUID) {
        guard globalButtons.first?.id != id else { return }
        configuration.globalButtons[controllerProfile.id]?.removeAll { $0.id == id }
    }
    func saveMapping(_ mapping: ButtonMapping, input: ControllerInput, gesture: Gesture) {
        saveMappings([gesture: mapping], input: input)
    }
    func saveMappings(_ actions: [Gesture: ButtonMapping], input: ControllerInput) {
        guard input != voiceInput else { return }
        var buttons = globalButtons
        if let index = buttons.firstIndex(where: { $0.input == input }) {
            buttons[index].actions.merge(actions) { _, edited in edited }
            configuration.globalButtons[controllerProfile.id] = buttons
        } else {
            editProfile { profile in
                for (gesture, mapping) in actions { profile.mapping[input, gesture] = mapping }
            }
        }
    }
    func profileNameError(_ name: String, excluding id: UUID? = nil) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "请输入方案名称。" }
        guard name.count <= 80 else { return "方案名称不能超过 80 个字符。" }
        return configuration.profiles.contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ? "已有同名方案，请换一个名称。" : nil
    }
    @discardableResult
    func saveProfile(name: String, replacing id: UUID? = nil) -> Bool {
        guard profileNameError(name, excluding: id) == nil else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id {
            guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return false }
            configuration.profiles[index].name = name
        } else {
            guard canAddProfile else {
                showNotice(.warning, "最多创建 100 个自定义方案。", issue: .profileLimit, resolvedWhen: { $0.canAddProfile })
                return false
            }
            let profile = KeyProfile(name: name)
            configuration.profiles.append(profile)
            selectProfile(profile.id)
        }
        return true
    }
    @discardableResult
    func duplicateProfile(_ id: UUID? = nil) -> UUID? {
        guard canAddProfile else {
            showNotice(.warning, "最多创建 100 个自定义方案。", issue: .profileLimit, resolvedWhen: { $0.canAddProfile })
            return nil
        }
        guard var copy = configuration.profiles.first(where: { $0.id == (id ?? selectedProfileID) }) else { return nil }
        copy.id = UUID()
        let base = String(copy.name.prefix(60)) + " 副本"
        copy.name = base
        var number = 2
        while profileNameError(copy.name) != nil {
            copy.name = base + " \(number)"; number += 1
        }
        configuration.profiles.append(copy); selectProfile(copy.id)
        return copy.id
    }
    func deleteProfile(_ id: UUID) {
        guard configuration.profiles.contains(where: { $0.id == id }) else { return }
        guard configuration.profiles.count > 1 else {
            showNotice(.warning, "至少保留一个方案。", issue: .lastProfile, resolvedWhen: { $0.configuration.profiles.count > 1 })
            return
        }
        var next = configuration
        next.profiles.removeAll { $0.id == id }
        next.harnesses.removeAll { $0.profileID == id && !$0.isBuiltIn }
        if defaultProfile.id == id { next.defaultProfileID = next.profiles[0].id }
        for index in next.harnesses.indices where next.harnesses[index].profileID == id {
            next.harnesses[index].profileID = next.defaultProfileID ?? next.profiles[0].id
        }
        if selectedProfileID == id { selectedProfileID = next.defaultProfileID ?? next.profiles[0].id }
        configuration = next
    }
    func addHarness() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if configuration.harnesses.contains(where: { $0.matches(bundleID: id) }) {
            showNotice(.warning, "这个应用已经有 Harness。", issue: .duplicateHarness(id), resolvedWhen: { model in
                !model.configuration.harnesses.contains { $0.matches(bundleID: id) }
            })
            return
        }
        configuration.harnesses.append(.init(applicationPath: url.path, bundleID: id, profileID: selectedProfileID))
    }
    func calibrate(_ device: ConnectedJoyCon) {
        guard let position = snapshots[device.id]?.stick else { return }
        var next = configuration
        next.centers[device.id] = .init(x: position.x, y: position.y)
        guard saveConfiguration(next) else { return }
        showNotice(.success, "已记录 \(device.profile.name) 的摇杆中心。")
    }
    func refreshPermissions() {
        let allowed = AXIsProcessTrusted()
        if accessibility && !allowed { engine.cancel(); macros.cancel() }
        accessibility = allowed; inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openPrivacy("Privacy_Accessibility")
    }
    func requestInputMonitoring() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent); openPrivacy("Privacy_ListenEvent") }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            clearNotice(for: .login)
        } catch { showNotice(.error, "登录项设置失败：\(error.localizedDescription)", issue: .login) }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func exportConfiguration() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "JoyHarness.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigurationImportPreview.encodeBackup(configuration).write(to: url, options: .atomic)
            clearNotice(for: .export)
            showNotice(.success, "配置已导出。")
        } catch { showNotice(.error, "导出失败：\(error.localizedDescription)", issue: .export) }
    }
    func importConfiguration() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importConfiguration(from: url)
    }
    func importConfiguration(from url: URL) {
        do {
            presentConfigurationPreview(try ConfigurationImportPreview.read(from: url))
            clearNotice(for: .importFile)
        } catch { showNotice(.error, "导入失败：\(error.localizedDescription)", issue: .importFile) }
    }
    func previewConfigurationRecovery() {
        guard let recovery = storedConfiguration.recovery else { return }
        do {
            let restored = try recovery.configuration.validated()
                .addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().addingBuiltInPhrases().validated()
            presentConfigurationPreview(.init(
                source: recovery.date.formatted(date: .abbreviated, time: .shortened) + " 的替换前备份",
                isRecovery: true, configuration: restored, editingProfileID: recovery.editingProfileID
            ))
            clearNotice(for: .recovery)
        } catch { showNotice(.error, "恢复失败：\(error.localizedDescription)", issue: .recovery) }
    }
    private func presentConfigurationPreview(_ preview: ConfigurationImportPreview) {
        phrasePicker?.model.dismiss()
        macros.cancel()
        harnessFocusRequest = UUID()
        harnessComposerFocus.cancel()
        pendingConfigurationImport = preview
    }
    func confirmConfigurationImport(_ id: UUID) throws {
        guard let preview = pendingConfigurationImport, preview.id == id else {
            throw ConfigurationImportPreview.ImportError.stalePreview
        }
        let recovery = ConfigurationRecovery(date: Date(), configuration: configuration, editingProfileID: selectedProfileID)
        try installConfiguration(.init(configuration: preview.configuration, recovery: recovery))
        let profiles = preview.configuration.profiles
        selectedProfileID = profiles.first { $0.id == preview.editingProfileID }?.id
            ?? preview.configuration.defaultProfileID ?? profiles[0].id
        pendingPhraseDeletion = nil
        phraseDeletionUndoStack.removeAll()
        pendingConfigurationImport = nil
        showNotice(.success, preview.isRecovery ? "配置已恢复。已保存恢复前的配置。" : "配置已导入。已保存替换前的配置。")
    }
    @discardableResult
    func saveConfiguration(_ configuration: Configuration) -> Bool {
        do {
            try commitConfiguration(configuration)
            return true
        } catch {
            showNotice(.error, "配置保存失败。\(error.localizedDescription)", issue: .configurationSave)
            return false
        }
    }
    func commitConfiguration(_ configuration: Configuration) throws {
        try installConfiguration(.init(configuration: configuration, recovery: storedConfiguration.recovery))
    }

    private func installConfiguration(_ stored: StoredConfiguration) throws {
        let previous = storedConfiguration.configuration
        let globalsChanged = previous.globalButtons != stored.configuration.globalButtons
            || previous.voiceButtons != stored.configuration.voiceButtons
        try SettingsStorage.write(stored, SettingsKeys.configuration, defaults: defaults)
        storedConfiguration = stored
        clearNotice(for: .configurationSave)
        let unresolved = notices.filter { $0.resolvedWhen?(self) != true }
        if unresolved.count != notices.count { notices = unresolved }
        applyProfile()
        if globalsChanged { engine.refreshPausedMapping() }
    }
    private func applyProfile() {
        let front = preview ? nil : NSWorkspace.shared.frontmostApplication
        frontmostApp = front?.localizedName ?? "当前应用"
        let binding = configuration.harnesses.first { $0.enabled && $0.matches(bundleID: front?.bundleIdentifier) }
        let id = binding?.profileID ?? defaultProfile.id
        var profile = configuration.profiles.first { $0.id == id } ?? selectedProfile
        profile.mapping = configuration.effectiveMapping(profile.mapping, for: controllerProfile)
        let mouseButtons = configuration.mouseButtons[controllerProfile.id] ?? .init()
        if activeProfileID != profile.id || engine.profile != profile || engine.deadzone != configuration.deadzone || engine.speed != configuration.pointerSpeed || engine.centers != configuration.centers || engine.mouseButtonBindings != mouseButtons {
            let previousMode = currentStickMode(for: controllerProfile.side)
            macros.cancel()
            engine.configure(profile: profile, deadzone: configuration.deadzone, speed: configuration.pointerSpeed, centers: configuration.centers, mouseButtons: mouseButtons)
            activeProfileID = profile.id
            if previousMode != currentStickMode(for: controllerProfile.side) { onMenuChange?() }
        }
    }
    private func perform(_ mapping: ButtonMapping, pressed: Bool) {
        if pressed && phrasePicker?.model.isPresented == true { return }
        if mapping.action == .toggleMode { if pressed { toggleMapping() }; return }
        if [.cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode].contains(mapping.action) {
            if pressed, enabled, !recordingShortcut {
                engine.cycleStickMode(for: controllerProfile.side)
            }
            return
        }
        if let target = mapping.action.harnessFocusTarget {
            if pressed, canSend { focusHarness(target) }
            return
        }
        guard canSend || !pressed else { return }
        switch mapping.action {
        case .phrase: if pressed { sender.typeText(mapping.text ?? "") }
        case .openPhrases:
            if pressed, enabled, let phrasePicker {
                macros.cancel()
                harnessFocusRequest = UUID()
                harnessComposerFocus.cancel()
                engine.setInputCaptured(true)
                phrasePicker.show(phrases: configuration.phrases, assignments: configuration.phraseAssignments)
                if let id = controllerSelection.deviceID, let snapshot = snapshots[id] {
                    phrasePicker.model.receive(snapshot, center: configuration.centers[id],
                                               deadzone: configuration.deadzone, baseline: true)
                }
            }
        case .macro: if pressed, let macro = configuration.macros.first(where: { $0.id == mapping.macroID }) {
            macros.run(macro, library: configuration.macros)
        }
        default:
            if pressed {
                let count = postedHolds[mapping] ?? 0
                postedHolds[mapping] = count + 1
                if count == 0 { sender.send(mapping, pressed: true) }
            } else if let count = postedHolds[mapping] {
                if count > 1 { postedHolds[mapping] = count - 1 }
                else { postedHolds[mapping] = nil; sender.send(mapping, pressed: false) }
            }
        }
    }

    private func focusHarness(_ target: HarnessFocusTarget) {
        guard let application = HarnessApplication.defaults.first(where: { $0.id == target.rawValue }) else { return }
        let harness = configuration.harnesses.first { $0.builtIn == application }
            ?? HarnessBinding(applicationPath: application.defaultApplicationPath,
                              bundleID: application.bundleIdentifiers[0], profileID: selectedProfileID)
        guard let installedURL = harness.installedApplicationURL else { return }
        harnessComposerFocus.cancel()
        let request = UUID(); harnessFocusRequest = request
        let runningApplication = NSWorkspace.shared.runningApplications.first { application in
            !application.isTerminated && harness.matches(applicationPath: application.bundleURL?.path,
                                                         bundleIdentifier: application.bundleIdentifier)
        }
        HarnessApplicationFocus.perform(installedURL: installedURL, runningProcessID: runningApplication?.processIdentifier,
                                        focusRunning: { [weak self] processID in
            guard let self, self.enabled, self.canSend, self.harnessFocusRequest == request else { return }
            let result = HarnessApplicationActivation.perform(processID: processID, isAvailable: {
                guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else { return false }
                return harness.matches(applicationPath: application.bundleURL?.path, bundleIdentifier: application.bundleIdentifier)
            })
            if result != .unavailable, AXIsProcessTrusted() { self.harnessComposerFocus.start(processID: processID, target: target) }
        }, launch: { url, completion in
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                DispatchQueue.main.async { completion(error == nil ? application?.processIdentifier : nil) }
            }
        })
    }
    func clearStatistics() { statistics = .init(); statsDirty = true; flushStatistics() }
    func copyDiagnostics() {
        let devices = devices.map { "\($0.profile.name): \($0.status)" }.joined(separator: "\n")
        let report = """
        JoyHarness \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        选中手柄：\(controllerTitle)
        映射：\(enabled ? "启用" : "暂停")
        辅助功能：\(accessibility)；输入监控：\(inputMonitoring)
        \(hidStatus)
        \(bleStatus)
        \(devices)
        """
        copyToPasteboard(report, confirmation: "诊断信息已复制。")
    }
    func copyToPasteboard(_ text: String, confirmation: String) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            showNotice(.error, "无法写入剪贴板，请重试。", issue: .clipboard)
            return
        }
        clearNotice(for: .clipboard)
        showNotice(.success, confirmation)
    }
    func showNotice(_ level: DashboardNotice.Level, _ detail: String, issue: DashboardNotice.Issue? = nil,
                    resolvedWhen: (@MainActor (DashboardModel) -> Bool)? = nil) {
        let notice = DashboardNotice(level: level, detail: detail, issue: issue, resolvedWhen: resolvedWhen)
        notices = notices.filter { $0.issue != issue } + [notice]
        guard let duration = level.autoDismissAfter else { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self, id = notice.id] in
            do { try await clock.sleep(until: deadline) } catch { return }
            self?.dismissNotice(id)
        }
    }
    func dismissNotice(_ id: UUID) {
        guard let notice = notices.first(where: { $0.id == id }) else { return }
        if notice.level.autoDismissAfter != nil {
            noticeTimer?.cancel()
            noticeTimer = nil
        }
        notices.removeAll { $0.id == id }
    }
    func clearNotice(for issue: DashboardNotice.Issue) {
        guard let notice = notices.first(where: { $0.issue == issue }) else { return }
        dismissNotice(notice.id)
    }
    private func flushStatistics() {
        guard statsDirty else { return }; statsDirty = false
        SettingsStorage.save(statistics, SettingsKeys.statistics, defaults: defaults)
    }
}
