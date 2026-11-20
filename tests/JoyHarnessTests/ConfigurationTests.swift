import CoreGraphics
import Foundation
import Testing
@testable import JoyHarness

struct ConfigurationTests {
    @Test func roundTripAllFeatures() throws {
        var config = Configuration()
        let profile = config.profiles[0]
        config.defaultProfileID = profile.id
        config.harnesses = [.init(applicationPath: "/Applications/Safari.app", bundleID: "com.apple.Safari", profileID: profile.id)]
        config.macros = [.init(name: "复制并粘贴", steps: [.init(mapping: .init(action: .copy)), .init(mapping: .init(action: .paste))])]
        config.profiles[0].mapping[.a, .long] = .init(action: .macro, macroID: config.macros[0].id)
        config.profiles[0].mapping[.c] = .init(action: .recordedShortcut, shortcut: .init(keyCode: 9, modifiers: 0x100000, label: "⌘V"))
        config.centers["ble-test"] = .init(x: 2020, y: 2080)
        let copy = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)).validated()
        #expect(copy == config)
    }
    @Test func invalidConfigurationRejected() {
        var config = Configuration(); config.profiles = []
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.version = 9
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.deadzone = 1
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.profiles.append(config.profiles[0])
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.harnesses = [.init(applicationPath: "/tmp/X.app", bundleID: "x", profileID: UUID())]
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.macros = [.init(steps: [.init(mapping: .init(action: .macro))])]
        #expect(throws: Error.self) { try config.validated() }
        config = Configuration(); config.macros = [.init(steps: [.init(delay: -1)])]
        #expect(throws: Error.self) { try config.validated() }
    }
    @Test func danglingAndIncompleteActionsRejected() {
        var config = Configuration()
        config.profiles[0].mapping[.a] = .init(action: .macro, macroID: UUID())
        #expect(throws: Error.self) { try config.validated() }
        config.profiles[0].mapping[.a] = .init(action: .recordedShortcut)
        #expect(throws: Error.self) { try config.validated() }
        config.profiles[0].mapping[.a] = .init(action: .openApplication, applicationPath: "relative.app")
        #expect(throws: Error.self) { try config.validated() }
    }
    @Test func corruptSettingsPreservedAndDomainsIsolated() throws {
        let suite = "JoyHarness.tests.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = Data("{broken".utf8); defaults.set(bad, forKey: "JoyHarness.test")
        #expect(SettingsStorage.load(Configuration.self, "test", defaults: defaults) == nil)
        #expect(defaults.data(forKey: "JoyHarness.recovery.test") == bad)
        SettingsStorage.save(Configuration(), "config", defaults: defaults)
        #expect(SettingsStorage.load(Configuration.self, "config", defaults: defaults) != nil)
        #expect(defaults.data(forKey: "RcHarness.config") == nil)
    }
    @Test func statisticsDoNotStoreContent() throws {
        var stats = UsageStatistics(); stats.record(.a); stats.record(.a); stats.record(.c)
        #expect(stats.total == 3); #expect(stats.days.count == 1)
        let json = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        #expect(!json.contains("text")); #expect(!json.contains("application"))
    }
    @Test func systemEventsUseInjectedSink() {
        var events: [CGEvent] = []
        let sender = SystemEventSender(postEvent: { events.append($0) })
        sender.send(.init(action: .rightCommand), pressed: true)
        sender.send(.init(action: .rightCommand), pressed: false)
        #expect(events.count == 2)
        #expect(events[0].type == .flagsChanged || events[0].type == .keyDown)
        #expect(events[0].flags.contains(.maskCommand))
        #expect(!events[1].flags.contains(.maskCommand))
        events.removeAll()
        sender.send(.init(action: .recordedShortcut, shortcut: .init(keyCode: 8, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘C")), pressed: true)
        #expect(events.count == 2)
        #expect(events[0].getIntegerValueField(.keyboardEventKeycode) == 8)
        #expect(events[1].type == .keyUp)
    }
    @Test func joystickDragAndScrollUseInjectedSink() {
        var events: [CGEvent] = []
        let sender = SystemEventSender(cursorLocation: { CGPoint(x: 10, y: 10) }, postEvent: { events.append($0) })
        sender.send(.init(action: .mouseLeft), pressed: true)
        sender.pointer(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 25, y: 30))
        sender.send(.init(action: .mouseLeft), pressed: false)
        sender.pointer(from: CGPoint(x: 25, y: 30), to: CGPoint(x: 25, y: 30))
        sender.pointer(from: CGPoint(x: 25, y: 30), to: CGPoint(x: 40, y: 25))
        sender.scroll(x: 1, y: 2)
        #expect(events.map(\.type) == [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved, .scrollWheel])
        #expect(events[1].location == CGPoint(x: 25, y: 30))
        #expect(events[1].getIntegerValueField(.mouseEventDeltaX) == 15)
        #expect(events[1].getIntegerValueField(.mouseEventDeltaY) == 20)
        #expect(events[3].getIntegerValueField(.mouseEventDeltaY) == -5)
    }

    @Test func mouseButtonsReportOneClickOnBothEdges() {
        for (action, down, up) in [
            (RemoteAction.mouseLeft, CGEventType.leftMouseDown, CGEventType.leftMouseUp),
            (.mouseRight, .rightMouseDown, .rightMouseUp)
        ] {
            var events: [CGEvent] = []
            let sender = SystemEventSender(cursorLocation: { .zero }, postEvent: { events.append($0) })
            sender.send(.init(action: action), pressed: true)
            sender.send(.init(action: action), pressed: false)
            #expect(events.map(\.type) == [down, up])
            #expect(events.map { $0.getIntegerValueField(.mouseEventClickState) } == [1, 1])
        }
    }
    @Test func unicodeAndApplicationActionsUseInjectedSinks() {
        var events: [CGEvent] = [], apps: [URL] = []
        let sender = SystemEventSender(postEvent: { events.append($0) }, openApplication: { apps.append($0) })
        sender.typeText("你好 🎮 " + String(repeating: "a", count: 40))
        #expect(events.count >= 6); #expect(events.count % 2 == 0)
        sender.send(.init(action: .openApplication, applicationPath: "/Applications/Safari.app"), pressed: true)
        #expect(apps.map(\.path) == ["/Applications/Safari.app"])
    }
}

@MainActor
struct ModelTests {
    @Test func configurationPreviewAndRecoverySurviveRelaunch() throws {
        let suite = "JoyHarness.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = DashboardModel(defaults: defaults, preview: true)
        model.duplicateProfile()
        try model.saveCustomMacroTag(name: "日常工作")
        let tag = try #require(model.customMacroTags.first)
        let macroID = try #require(model.addMacro(tagIDs: [tag.id]))
        let oldSelection = model.selectedProfileID
        let original = model.configuration
        var incoming = Configuration()
        incoming.pointerSpeed = 20
        incoming.customMacroTags = [.init(id: "demo", name: "演示")]
        incoming.macros = [.init(name: "演示动作", tagIDs: ["demo", "unknown"])]
        try ConfigurationImportPreview.encodeBackup(incoming).write(to: url)

        model.importConfiguration(from: url)
        let cancelled = try #require(model.pendingConfigurationImport)
        model.pendingConfigurationImport = nil
        #expect(throws: ConfigurationImportPreview.ImportError.stalePreview) {
            try model.confirmConfigurationImport(cancelled.id)
        }
        #expect(model.configuration == original)
        #expect(model.configurationRecoveryDate == nil)

        model.importConfiguration(from: url)
        let preview = try #require(model.pendingConfigurationImport)
        #expect(preview.configuration.macros.count == DefaultMacros.all.count + 1)
        #expect(preview.configuration.customMacroTags == incoming.customMacroTags)
        #expect(preview.configuration.macros.first?.tagIDs == ["demo"])
        #expect(preview.configuration.phrases == DefaultPhrases.all)
        #expect(preview.configuration.phraseAssignments == DefaultPhrases.assignments(for: DefaultPhrases.all))
        incoming.pointerSpeed = 25
        try JSONEncoder().encode(incoming).write(to: url)
        try model.confirmConfigurationImport(preview.id)
        #expect(model.configuration.pointerSpeed == 20)
        #expect(model.pendingConfigurationImport == nil)
        #expect(model.configurationRecoveryDate != nil)
        model.configuration.pointerSpeed = 23
        let edited = model.configuration

        let relaunched = DashboardModel(defaults: defaults, preview: true)
        relaunched.previewConfigurationRecovery()
        let recovery = try #require(relaunched.pendingConfigurationImport)
        #expect(recovery.isRecovery)
        #expect(recovery.configuration == original)
        #expect(relaunched.configuration == edited)
        try relaunched.confirmConfigurationImport(recovery.id)
        #expect(relaunched.configuration == original)
        #expect(relaunched.selectedProfileID == oldSelection)

        let restored = DashboardModel(defaults: defaults, preview: true)
        #expect(restored.configuration == original)
        #expect(restored.savedMacros.first { $0.id == macroID }?.tagIDs == [tag.id])
        #expect(restored.selectedProfileID == oldSelection)
        restored.previewConfigurationRecovery()
        #expect(restored.pendingConfigurationImport?.configuration == edited)
        let stored = try #require(defaults.data(forKey: "JoyHarness.configuration.v1"))
        #expect(try JSONDecoder().decode(Configuration.self, from: stored) == original)
    }

    @Test func unrelatedJSONCannotReplaceConfiguration() throws {
        let suite = "JoyHarness.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{}".utf8).write(to: url)
        let model = DashboardModel(defaults: defaults, preview: true)
        let original = model.configuration
        model.importConfiguration(from: url)
        #expect(model.pendingConfigurationImport == nil)
        #expect(model.notices.last?.level == .error)
        #expect(model.notices.last?.detail.hasPrefix("导入失败") == true)
        #expect(model.configuration == original)
        #expect(model.configurationRecoveryDate == nil)
        model.showNotice(.success, "诊断信息已复制。")
        #expect(model.notices.contains { $0.issue == .importFile })
        try ConfigurationImportPreview.encodeBackup(original).write(to: url)
        model.importConfiguration(from: url)
        #expect(model.pendingConfigurationImport != nil)
        #expect(!model.notices.contains { $0.issue == .importFile })
        #expect(model.notices.last?.level == .success)
    }

    @Test func profileDeletionRemovesBindingsAtomically() {
        let suite = "JoyHarness.tests.\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var config = Configuration(); config.profilePresetsVersion = DefaultKeyProfiles.version
        SettingsStorage.save(config, "configuration.v1", defaults: defaults)
        let model = DashboardModel(defaults: defaults, preview: true)
        let old = model.selectedProfileID
        model.duplicateProfile()
        #expect(model.selectedProfileID != old); #expect(model.configuration.profiles.count == 2)
        model.configuration.harnesses = [.init(applicationPath: "/tmp/X.app", bundleID: "x", profileID: old)]
        model.deleteProfile(old)
        #expect(model.configuration.profiles.count == 1); #expect(model.configuration.harnesses.isEmpty)
        #expect((try? model.configuration.validated()) != nil)
        model.deleteProfile(model.selectedProfileID)
        #expect(model.notices.last?.level == .warning)
        model.duplicateProfile()
        #expect(model.notices.isEmpty)
        model.deleteProfile(model.selectedProfileID)
        #expect(model.configuration.profiles.count == 1)
    }
}

extension ModelTests {
    @Test func exportedBackupUsesImportSizeLimit() throws {
        var configuration = Configuration().addingBuiltInMacros().addingBuiltInProfiles()
            .addingBuiltInHarnesses().addingBuiltInPhrases()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigurationImportPreview.encodeBackup(configuration).write(to: url)
        #expect(try ConfigurationImportPreview.read(from: url).configuration == configuration)

        let text = String(repeating: "示例", count: 4500)
        configuration.phrases += (0..<100).map { .init(title: "常用语 \($0)", text: text) }
        #expect(throws: ConfigurationImportPreview.ImportError.fileTooLarge) {
            try ConfigurationImportPreview.encodeBackup(configuration)
        }
    }
}
