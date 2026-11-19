import CoreGraphics
import Foundation
import Testing
@testable import JoyHarness

struct DefaultMacroTests {
    @Test func catalogHasAllSixAppsAndStableExecutableSteps() throws {
        let counts: [Int] = [DefaultMacros.chatgpt.count, DefaultMacros.claude.count, DefaultMacros.cursor.count,
                             DefaultMacros.deepSeek.count, DefaultMacros.workBuddy.count, DefaultMacros.openCode.count]
        #expect(counts == [26, 39, 35, 27, 24, 59])
        let config = try Configuration().addingBuiltInMacros().validated()
        #expect(config.macros == DefaultMacros.all)
        #expect(config.macros.count == 210)
        #expect(Set(config.macros.map(\.id)).count == 210)
        #expect(Set(config.macros.map(\.name)).count == 210)
        let steps = config.macros.flatMap(\.steps)
        #expect(Set(steps.map(\.id)).count == 211)
        #expect(Set(steps.map(\.id)).isDisjoint(with: Set(config.macros.map(\.id))))
        #expect(steps.allSatisfy { $0.mapping.action == .recordedShortcut && $0.mapping.shortcut != nil })
        #expect(config.addingBuiltInMacros() == config)
    }

    @Test func legacyImportPreservesEditedRenamedAndSameNameActionsAndReferences() throws {
        var config = Configuration()
        let sameName = ActionMacro(name: "  chatgpt-新建会话  ", steps: [.init(mapping: .init(action: .copy))])
        var renamed = DefaultMacros.openCode[0]
        renamed.name = "我的新会话"; renamed.steps = [.init(mapping: .init(action: .paste), delay: 0.8)]
        config.macros = [sameName, renamed]
        config.profiles[0].mapping[.a] = .init(action: .macro, macroID: sameName.id)
        let imported = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
            .validated().addingBuiltInMacros().validated()
        #expect(imported.macros.count == 210)
        #expect(Array(imported.macros.prefix(2)) == config.macros)
        #expect(imported.profiles == config.profiles)
        #expect(!imported.macros.contains { $0.id == DefaultMacros.chatgpt[0].id })
        #expect(imported.macroPresetsVersion == DefaultMacros.version)
        var deleted = imported
        deleted.macros.removeAll { $0.id == renamed.id }
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(deleted))
            .addingBuiltInMacros()
        #expect(restored == deleted)
    }

    @Test func olderPresetVersionAddsOnlyNewGroupsAndLeavesEarlierDeletionsAlone() throws {
        var config = Configuration()
        config.macroPresetsVersion = 5
        config.macros = [DefaultMacros.chatgpt[0]]
        let upgraded = try config.addingBuiltInMacros().validated()
        #expect(upgraded.macros == config.macros + DefaultMacros.openCode)
        #expect(upgraded.addingBuiltInMacros() == upgraded)
    }

    @Test func legacyTagsMigrateAndExplicitEmptyTagsSurvive() throws {
        let preset = DefaultMacros.workBuddy[0]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any])
        json.removeValue(forKey: "tagIDs")
        let legacy = try JSONDecoder().decode(ActionMacro.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.tagIDs == ["workbuddy"])
        #expect(legacy.matches(tagID: "workbuddy", query: "新建对话"))
        #expect(!legacy.matches(tagID: "chatgpt", query: ""))
        #expect(!legacy.matches(tagID: nil, query: "不存在的动作"))
        json["tagIDs"] = [] as [String]
        let untagged = try JSONDecoder().decode(ActionMacro.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(untagged.tagIDs.isEmpty)
        #expect(untagged.matches(tagID: nil, query: "workbuddy"))
        let custom = ActionMacro()
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as? [String: Any])
        json.removeValue(forKey: "tagIDs")
        #expect(try JSONDecoder().decode(ActionMacro.self, from: JSONSerialization.data(withJSONObject: json)).tagIDs == ["general"])
    }

    @Test func fullCustomLibraryCanGainPresetsAndRoundTrip() throws {
        var config = Configuration()
        config.macros = (0..<100).map { ActionMacro(name: "我的动作\($0)") }
        let upgraded = try config.addingBuiltInMacros().validated()
        #expect(upgraded.macros.count == 310)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(upgraded)).validated() == upgraded)
    }
}

@MainActor
struct DefaultMacroRuntimeTests {
    @Test func representativeShortcutsPostExpectedKeysAndModifiers() throws {
        let cases: [(String, Int64, CGEventFlags)] = [
            ("ChatGPT-新建会话", 0x2D, .maskCommand),
            ("Claude-打开侧边聊天", 0x29, .maskCommand),
            ("Cursor-切换到下一条消息", 0x30, []),
            ("DeepSeek-添加工作区", 0x1F, .maskCommand),
            ("WorkBuddy-上一个标签页", 0x30, [.maskControl, .maskShift]),
            ("OpenCode-上一个会话", 0x7E, .maskAlternate),
        ]
        for (name, key, flags) in cases {
            let macro = try #require(DefaultMacros.all.first { $0.name == name })
            let clock = TestClock(), executor = MacroExecutor(schedule: clock.schedule)
            var events: [CGEvent] = []
            let sender = SystemEventSender(postEvent: { events.append($0) })
            executor.output = { sender.send($0, pressed: $1) }
            executor.run(macro); clock.advance(1)
            #expect(events.map(\.type) == [.keyDown, .keyUp])
            #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [key, key])
            #expect(events[0].flags == flags)
        }
    }

    @Test func deepSeekStopPostsTwoEscapesOneTenthSecondApartAndCancels() throws {
        let macro = try #require(DefaultMacros.deepSeek.first { $0.name == "DeepSeek-停止回复（双击 Esc）" })
        let clock = TestClock(), executor = MacroExecutor(schedule: clock.schedule)
        var keys: [UInt16] = []
        executor.output = { mapping, pressed in if pressed, let shortcut = mapping.shortcut { keys.append(shortcut.keyCode) } }
        executor.run(macro); clock.advance(0)
        #expect(keys == [0x35])
        clock.advance(0.09); #expect(keys == [0x35])
        clock.advance(0.02); #expect(keys == [0x35, 0x35])
        keys = []; executor.run(macro); clock.advance(0); executor.cancel(); clock.advance(1)
        #expect(keys == [0x35])
    }

    @Test func editsAndDeletionsSurviveModelRestartAndBackupImport() throws {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        #expect(model.configuration.macros == DefaultMacros.all)
        model.configuration.macros[0].name = "我的动作"
        model.configuration.macros[0].steps = [.init(mapping: .init(action: .copy))]
        model.configuration.macros[0].tagIDs = []
        model.configuration.macros.removeLast()
        let restored = DashboardModel(defaults: defaults, preview: true)
        #expect(restored.configuration == model.configuration)
        let imported = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(model.configuration))
            .validated().addingBuiltInHarnesses().addingBuiltInMacros().validated()
        #expect(imported == model.configuration)
        for id in model.configuration.macros.map(\.id) { model.deleteMacro(id) }
        #expect(DashboardModel(defaults: defaults, preview: true).configuration.macros.isEmpty)
    }
}
