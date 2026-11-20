import AppKit
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: DashboardModel?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var lock: SingleInstanceLock?
    private let arguments = ProcessInfo.processInfo.arguments

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = arguments.firstIndex(of: "--render-settings") {
            guard index + 1 < arguments.count else { NSApp.terminate(nil); return }
            // Finish launching before activating the preview window, so native
            // controls are rendered in the same active state as the real app.
            DispatchQueue.main.async { [self] in
                do { try renderPages(directory: arguments[index + 1]) }
                catch { Log.app.error("Render failed: \(error.localizedDescription, privacy: .private)"); exit(1) }
                NSApp.terminate(nil)
            }
            return
        }
        do {
            lock = try SingleInstanceLock(path: NSHomeDirectory() + "/Library/Application Support/JoyHarness/instance.lock")
        } catch SingleInstanceLock.Failure.alreadyRunning {
            NSRunningApplication.runningApplications(withBundleIdentifier: "vip.tokenzz.joyharness")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?.activate()
            NSApp.terminate(nil); return
        } catch { Log.app.error("Cannot acquire instance lock: \(error.localizedDescription, privacy: .private)"); NSApp.terminate(nil); return }
        let model = DashboardModel(); self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        model.onMenuChange = { [weak self] in self?.updateMenu() }
        updateMenu(); makeWindow(model); model.start(); if model.openAtLaunch { showWindow() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    private func makeWindow(_ model: DashboardModel) {
        let window = Self.dashboardWindow(rootView: DashboardView(model: model))
        window.setFrameAutosaveName("JoyHarness.main")
        window.center()
        self.window = window
    }
    static let defaultWindowSize = CGSize(width: 1120, height: 820)
    static func dashboardWindow<Content: View>(rootView: Content, size: CGSize = defaultWindowSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "JoyHarness"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: rootView)
        // Keep the window at the requested content size across page changes.
        view.sizingOptions = []
        window.contentView = view
        window.contentMinSize = DashboardStyle.minimumWindowSize
        window.setContentSize(size)
        return window
    }
    @objc private func showWindow() { NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }
    @objc private func toggleMapping() { model?.toggleMapping() }
    @objc private func rescan() { model?.rescan() }
    @objc private func selectController(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let profile = JoyConProfile.all.first(where: { "profile:" + $0.id == id }) { model?.selectControllerProfile(profile) }
        else { model?.selectDevice(id) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    private func updateMenu() {
        guard let model else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "JoyHarness · \(model.connectedCount) 个手柄", action: nil, keyEquivalent: "")
        let selected = menu.addItem(withTitle: "当前：" + model.controllerTitle, action: nil, keyEquivalent: "")
        selected.submenu = ControllerDeviceMenuContent.make(model: model, target: self, action: #selector(selectController(_:)))
        let mode = model.currentStickMode(for: model.controllerProfile.side)
        let mouseModeActive = model.enabled && model.selectedDeviceReady && mode == .pointer
        if let button = statusItem?.button {
            button.image = mouseModeActive ? BrandAssets.mouseMenuBarIcon : BrandAssets.menuBarIcon
            button.needsDisplay = true
        }
        let status = model.enabled ? mode.label : "映射已暂停"
        statusItem?.button?.toolTip = "JoyHarness · \(status)"
        let modeItem = menu.addItem(withTitle: "当前模式：\(mode.label)", action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
        modeItem.isEnabled = false
        menu.addItem(.separator())
        for (title, action, key) in [("打开主面板", #selector(showWindow), ","),
                                     (model.enabled ? "暂停映射" : "恢复映射", #selector(toggleMapping), ""),
                                     ("重新扫描手柄", #selector(rescan), "")] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 JoyHarness", action: #selector(quit), keyEquivalent: "q"); quit.target = self
        statusItem?.menu = menu
    }
    private func renderPages(directory: String) throws {
        let directory = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "JoyHarness.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        if let index = arguments.firstIndex(of: "--controller"), index + 1 < arguments.count,
           let profile = JoyConProfile.all.first(where: { $0.id == arguments[index + 1] }) {
            model.selectControllerProfile(profile)
        }
        if let index = arguments.firstIndex(of: "--key-profile"), index + 1 < arguments.count,
           let application = HarnessApplication.defaults.first(where: { $0.id == arguments[index + 1] }) {
            let id = DefaultKeyProfiles.id(for: application)
            model.selectProfile(id); model.setDefaultProfile(id)
        }
        if arguments.contains("--populated") {
            model.configuration.harnesses.append(.init(applicationPath: "/System/Applications/Notes.app", bundleID: "com.apple.Notes", profileID: model.selectedProfileID))
            model.configuration.macros.append(.init(name: "复制并切换应用", steps: [.init(mapping: .init(action: .copy)), .init(mapping: .init(action: .paste))]))
            for day in 0...6 {
                let date = Calendar.current.date(byAdding: .day, value: -day, to: Date())!
                for _ in 0..<(day + 1) * 3 { model.statistics.record(.a, date: date) }
                for _ in 0..<(day + 1) { model.statistics.record(.c, date: date) }
            }
        }
        let macroTagPreview = arguments.contains("--macro-tag-preview")
        if macroTagPreview {
            try model.saveCustomMacroTag(name: "日常工作")
            try model.saveCustomMacroTag(name: "演示")
            if let macro = model.savedMacros.first, let tag = model.customMacroTags.first {
                model.updateMacroTags(macro.tagIDs.union([tag.id]), for: macro.id)
            }
        }
        let dark = arguments.contains("--dark")
        let size = arguments.contains("--narrow") ? DashboardStyle.minimumWindowSize : Self.defaultWindowSize
        let window = Self.dashboardWindow(
            rootView: DashboardView(model: model).environment(\.colorScheme, dark ? .dark : .light),
            size: size
        )
        guard let view = window.contentView else { throw RenderFailure.bitmap }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for page in DashboardPage.allCases {
            model.page = page
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
            try render(view, to: directory.appendingPathComponent(page.rawValue + ".png"))
        }
        if macroTagPreview {
            let manager = NSHostingView(rootView: MacroTagManagementSheet(model: model)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light))
            manager.appearance = window.appearance
            manager.frame.size = manager.fittingSize
            try render(manager, to: directory.appendingPathComponent("macro-tag-management.png"))
        }
        if arguments.contains("--notice-preview") {
            model.page = .settings
            let samples: [(DashboardNotice.Level, String, DashboardNotice.Issue?)] = [
                (.success, "配置已导出。", nil),
                (.information, "当前手柄已切换为「方向映射」。", nil),
                (.warning, "至少保留一个方案。请先创建另一个按键方案。", .lastProfile),
                (.error, "导入失败：配置文件格式无效，请选择 JoyHarness 导出的 JSON 文件。", .importFile),
            ]
            for (level, detail, issue) in samples {
                model.showNotice(level, detail, issue: issue)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
                try render(view, to: directory.appendingPathComponent("notice-\(level.rawValue).png"))
                if level != .error, let notice = model.notices.last { model.dismissNotice(notice.id) }
            }
            model.showNotice(.success, "诊断信息已复制。")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            try render(view, to: directory.appendingPathComponent("notice-stacked.png"))
            for notice in model.notices { model.dismissNotice(notice.id) }
        }
        if arguments.contains("--phrase-preview") {
            let picker = PhrasePickerController(onDismiss: {}, onOutput: { _ in })
            picker.show(phrases: model.configuration.phrases, assignments: model.configuration.phraseAssignments)
            defer { picker.model.dismiss() }
            guard let pickerView = picker.renderView else { throw RenderFailure.bitmap }
            pickerView.window?.appearance = window.appearance
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            try render(pickerView, to: directory.appendingPathComponent("phrase-picker.png"))
            window.makeKeyAndOrderFront(nil)
        }
        if arguments.contains("--configuration-preview") {
            model.page = .settings
            var incoming = model.configuration
            incoming.phraseAssignments = .init()
            incoming.phrases = Array(incoming.phrases.prefix(3))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            model.pendingConfigurationImport = .init(source: "JoyHarness-配置备份.json", isRecovery: false, configuration: incoming)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            guard let preview = model.pendingConfigurationImport,
                  let importView = window.attachedSheet?.contentView else { throw RenderFailure.sheet }
            try render(importView, to: directory.appendingPathComponent("configuration-import.png"))
            try model.confirmConfigurationImport(preview.id)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            model.previewConfigurationRecovery()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            guard let recoveryView = window.attachedSheet?.contentView else { throw RenderFailure.sheet }
            try render(recoveryView, to: directory.appendingPathComponent("configuration-recovery.png"))
            model.pendingConfigurationImport = nil
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            try render(view, to: directory.appendingPathComponent("settings.png"))
        }
        if arguments.contains("--mapping-editor-preview"), let macro = model.configuration.macros.first {
            model.page = .mapping
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            model.macroBindingRequest = macro.id
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            guard let editorView = window.attachedSheet?.contentView else { throw RenderFailure.sheet }
            try render(editorView, to: directory.appendingPathComponent("mapping-editor.png"))
        }
        window.orderOut(nil)
    }
    private func render(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw RenderFailure.bitmap }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw RenderFailure.bitmap }
        try png.write(to: url)
    }
    enum RenderFailure: Error { case bitmap, sheet }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = ApplicationDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
