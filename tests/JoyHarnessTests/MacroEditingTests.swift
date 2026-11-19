import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct MacroEditingTests {
    private func withModel(_ body: (DashboardModel) throws -> Void) rethrows {
        let suite = "JoyHarness.MacroEditingTests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(DashboardModel(defaults: defaults, preview: true))
    }

    @Test func namesValidateAndEditsSaveImmediatelyWithoutChangingReferences() throws {
        try withModel { model in
            let id = try #require(model.addMacro(tagIDs: ["chatgpt", "claude"]))
            let second = try #require(model.addMacro())
            #expect(model.savedMacros.last?.name == "新组合动作 2")
            #expect(!model.renameMacro(id, name: "  "))
            #expect(!model.renameMacro(id, name: "chatgpt-新建会话"))
            #expect(model.renameMacro(id, name: "  我的会话  "))
            model.updateMacroTags(["workbuddy", "opencode"], for: id)
            let steps = [MacroStep(mapping: .init(action: .copy), delay: 1.2)]
            #expect(model.updateMacroSteps(steps, for: id))
            let edited = try #require(model.savedMacros.first { $0.id == id })
            #expect(edited.name == "我的会话")
            #expect(edited.tagIDs == ["workbuddy", "opencode"])
            #expect(edited.steps == steps)
            #expect(model.updateMacroSteps([], for: second))
            #expect(!model.updateMacroSteps([.init(mapping: .init(action: .recordedShortcut))], for: id))
            let validated = try model.configuration.validated()
            #expect(validated == model.configuration)
        }
    }

    @Test func nestedMacrosExecuteInOrderWithChildAndParentDelays() throws {
        try withModel { model in
            let child = try #require(model.addMacro())
            let parent = try #require(model.addMacro())
            #expect(model.updateMacroSteps([.init(mapping: .init(action: .copy), delay: 0.2)], for: child))
            #expect(model.updateMacroSteps([
                .init(mapping: .init(action: .macro, macroID: child), delay: 0.3),
                .init(mapping: .init(action: .paste), delay: 0),
            ], for: parent))
            let macro = try #require(model.savedMacros.first { $0.id == parent })
            let plan = try MacroExecutionPlan(macro, macros: model.savedMacros)
            #expect(plan.events.map(\.mapping.action) == [.copy, .paste])
            #expect(plan.events.map(\.offset) == [0, 0.5])
            #expect(!model.canNestMacro(parent, in: child))
            #expect(!model.updateMacroSteps([.init(mapping: .init(action: .macro, macroID: parent))], for: child))
            let clock = TestClock(), executor = MacroExecutor(schedule: clock.schedule)
            var actions: [RemoteAction] = []
            executor.output = { if $1 { actions.append($0.action) } }
            executor.run(macro, library: model.savedMacros); clock.advance(0.49)
            #expect(actions == [.copy])
            clock.advance(0.02); #expect(actions == [.copy, .paste])
            actions = []; executor.run(macro, library: model.savedMacros)
            clock.advance(0); executor.cancel(); clock.advance(1)
            #expect(actions == [.copy])
            let validated = try model.configuration.validated()
            #expect(validated == model.configuration)
        }
    }

    @Test func deletionClearsBindingsAndNestedReferencesAtomically() throws {
        try withModel { model in
            let child = try #require(model.addMacro())
            let parent = try #require(model.addMacro())
            #expect(model.updateMacroSteps([.init(mapping: .init(action: .macro, macroID: child))], for: parent))
            model.editProfile { $0.mapping[.a] = .init(action: .macro, macroID: child) }
            model.deleteMacro(child)
            #expect(model.selectedProfile.mapping[.a].action == .disabled)
            #expect(model.savedMacros.first { $0.id == parent }?.steps.first?.mapping.action == .disabled)
            #expect(!model.savedMacros.contains { $0.id == child })
            let validated = try model.configuration.validated()
            #expect(validated == model.configuration)
        }
    }

    @Test func expansionLimitAndSelfReferencesAreRejected() throws {
        try withModel { model in
            let child = try #require(model.addMacro())
            let parent = try #require(model.addMacro())
            #expect(!model.canNestMacro(parent, in: parent))
            #expect(model.updateMacroSteps((0..<60).map { _ in .init() }, for: child))
            #expect(!model.updateMacroSteps([
                .init(mapping: .init(action: .macro, macroID: child)),
                .init(mapping: .init(action: .macro, macroID: child)),
            ], for: parent))
            let validated = try model.configuration.validated()
            #expect(validated == model.configuration)
            model.requestMacroBinding(child)
            #expect(model.page == .mapping)
            #expect(model.macroBindingRequest == child)
        }
    }

    @Test func recordingWaitsForKeyAndModifierReleaseAndCanCancel() throws {
        let session = ShortcutRecordingSession()
        var recordings: [RecordedShortcut] = []
        session.onCapture = { recordings.append($0) }
        func event(_ type: CGEventType, key: Int64, flags: CGEventFlags) throws {
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: UInt16(key), keyDown: type != .keyUp))
            event.type = type; event.flags = flags
            #expect(session.handle(type, event: event))
        }
        session.start()
        try event(.keyDown, key: 0x2D, flags: .maskCommand)
        try event(.keyUp, key: 0x2D, flags: .maskCommand)
        #expect(recordings.isEmpty)
        try event(.flagsChanged, key: 0x37, flags: [])
        #expect(recordings.count == 1)
        #expect(recordings[0].keyCode == 0x2D)
        #expect(recordings[0].modifiers == CGEventFlags.maskCommand.rawValue)
        session.start(); try event(.keyDown, key: 0x2D, flags: .maskCommand); session.stop()
        #expect(!session.isRecording)
        #expect(recordings.count == 1)
    }
}

extension MacroEditingTests {
    @Test func macroLimitPreservesLegacyConfigurationOnRelaunch() throws {
        let suite = "JoyHarness.MacroLimit.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var legacy = Configuration()
        legacy.profiles[0].name = "保留我的方案"
        legacy.macros = (0...Configuration.customMacroLimit).map { ActionMacro(name: "动作 \($0)") }
        SettingsStorage.save(legacy, "configuration.v1", defaults: defaults)
        let model = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(model.defaultProfile.name == "保留我的方案")
        #expect(model.configuration.customMacroCount == Configuration.customMacroLimit + 1)
        #expect(model.addMacro() == nil)
        model.deleteMacro(legacy.macros[0].id)
        #expect(model.addMacro() == nil)
        model.deleteMacro(legacy.macros[1].id)
        #expect(model.addMacro() != nil)
        #expect(model.addMacro() == nil)
        let reopened = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(reopened.configuration == model.configuration)
    }
}
