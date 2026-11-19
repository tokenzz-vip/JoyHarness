import Foundation
import Testing
@testable import JoyHarness

struct DefaultKeyProfileTests {
    @Test func freshConfigurationBindsSixIndependentAppProfiles() throws {
        let config = try Configuration().addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        #expect(config.profiles.count == 7)
        #expect(config.defaultProfileID == config.profiles[0].id)
        #expect(config.profilePresetsVersion == DefaultKeyProfiles.version)
        #expect(Set(config.harnesses.map(\.profileID)).count == 6)
        let newActions = ["ChatGPT-新建会话", "Claude-新建会话", "Cursor-新建会话（Command+N）", "DeepSeek-新建会话", "WorkBuddy-新建对话", "OpenCode-新建会话（Command+N）"]
        for (binding, newAction) in zip(config.harnesses, newActions) {
            let profile = try #require(config.profiles.first { $0.id == binding.profileID })
            #expect(profile.name == binding.name + " 按键方案")
            for stick in [ControllerInput.leftStick, .rightStick] {
                let macro = try #require(config.macros.first { $0.id == profile.mapping[stick, .double].macroID })
                #expect(macro.name == newAction)
                #expect(profile.mapping[stick, .long].action == .openPhrases)
            }
            for input in ControllerInput.allCases {
                #expect(profile.mapping[input] == RemoteMapping.defaults[input])
            }
            let left: [ControllerInput] = [.up, .right, .down, .left, .l, .zl, .minus, .leftSL, .leftSR]
            let right: [ControllerInput] = [.x, .a, .b, .y, .r, .zr, .plus, .rightSL, .rightSR]
            for (a, b) in zip(left, right) {
                #expect(profile.mapping[a, .double].action == .macro)
                #expect(profile.mapping[a, .double] == profile.mapping[b, .double])
                let macro = try #require(config.macros.first { $0.id == profile.mapping[a, .double].macroID })
                #expect(macro.name.hasPrefix(binding.name + "-"))
            }
        }
        #expect(config.addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses() == config)
    }

    @Test func legacyUpgradePreservesCustomMappingsBindingsAndNameConflicts() throws {
        var old = Configuration()
        old.profiles[0].mapping[.a] = .init(action: .paste)
        let custom = KeyProfile(name: "ChatGPT 按键方案")
        old.profiles.append(custom); old.defaultProfileID = custom.id
        old.harnesses = [.init(applicationPath: "/custom/WorkBuddy.app", bundleID: "com.workbuddy.workbuddy", profileID: custom.id, enabled: false)]
        let upgraded = try old.addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        #expect(Array(upgraded.profiles.prefix(2)) == old.profiles)
        #expect(upgraded.defaultProfileID == custom.id)
        #expect(upgraded.harnesses[0] == old.harnesses[0])
        #expect(upgraded.profiles[2].name == "ChatGPT 按键方案 2")
        #expect(upgraded.harnesses.dropFirst().allSatisfy { DefaultKeyProfiles.presetIDs.contains($0.profileID) })
        let imported = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(upgraded))
            .validated().addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        #expect(imported == upgraded)
    }

    @Test func presetResolutionKeepsRenamesSameNameMacrosAndDeletions() throws {
        var config = Configuration().addingBuiltInMacros()
        let chatgpt = HarnessApplication.defaults[0]
        var renamed = DefaultMacros.chatgpt[0]; renamed.name = "我的新会话"
        config.macros[0] = renamed
        let definition = try #require(config.macros.first { $0.name == "ChatGPT-转到最近聊天1" })
        config.macros.removeAll { $0.id == definition.id }
        let sameName = ActionMacro(name: " chatgpt-转到最近聊天1 ")
        config.macros.append(sameName)
        let deleted = try #require(config.macros.first { $0.name == "ChatGPT-转到最近聊天2" })
        config.macros.removeAll { $0.id == deleted.id }
        let profile = DefaultKeyProfiles.profile(for: chatgpt, macros: config.macros)
        #expect(profile.mapping[.leftStick, .double].macroID == renamed.id)
        #expect(profile.mapping[.up, .double].macroID == sameName.id)
        #expect(profile.mapping[.right, .double].action == .disabled)
        config = try config.addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        let id = config.profiles[1].id
        config.profiles[1].name = "我的 ChatGPT"
        config.profiles[1].mapping[.up, .double] = .init(action: .copy)
        config.profiles.remove(at: 2)
        config.harnesses.removeAll { $0.builtIn?.id == "claude" }
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
            .addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        #expect(restored.profiles == config.profiles)
        #expect(restored.profiles.first { $0.id == id }?.mapping[.up, .double].action == .copy)
        #expect(restored.harnesses.first { $0.builtIn?.id == "claude" }?.profileID == config.defaultProfileID)
    }

    @Test func fullCustomProfileLibraryCanUpgrade() throws {
        var config = Configuration()
        config.profiles = (0..<100).map { KeyProfile(name: "我的方案\($0)") }
        let upgraded = try config.addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses().validated()
        #expect(upgraded.profiles.count == 106)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(upgraded)).validated() == upgraded)
    }
}

@MainActor
struct KeyProfileModelTests {
    @Test func editingAndDuplicatingDoNotChangeDefaultAndPersistIndependently() throws {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        let original = model.defaultProfile.id
        let chatgpt = try #require(model.configuration.profiles.first { $0.name == "ChatGPT 按键方案" })
        model.selectProfile(chatgpt.id)
        #expect(model.mappingSummary(chatgpt.mapping[.up, .double]) == "转到最近聊天1")
        #expect(model.activeProfile.id == original)
        model.duplicateProfile(chatgpt.id)
        let duplicate = model.selectedProfile
        #expect(duplicate.id != chatgpt.id)
        #expect(duplicate.mapping == chatgpt.mapping)
        #expect(model.defaultProfile.id == original)
        model.setDefaultProfile(chatgpt.id)
        #expect(model.activeProfile.id == chatgpt.id)
        let restored = DashboardModel(defaults: defaults, preview: true)
        #expect(restored.selectedProfileID == duplicate.id)
        #expect(restored.defaultProfile.id == chatgpt.id)
        #expect(restored.configuration == model.configuration)
        model.deleteProfile(chatgpt.id)
        #expect(model.configuration.harnesses.first { $0.builtIn?.id == "chatgpt" }?.profileID == original)
        #expect(try model.configuration.validated() == model.configuration)
        #expect(DashboardModel(defaults: defaults, preview: true).configuration == model.configuration)
    }

    @Test func doublePressExecutesAppActionOnEveryControllerFamily() throws {
        let config = Configuration().addingBuiltInMacros().addingBuiltInProfiles()
        for profile in config.profiles.dropFirst() {
            for controller in JoyConProfile.all {
                let clock = TestClock(), gestures = GestureController(schedule: clock.schedule)
                let input: ControllerInput = controller.side == .left ? .leftStick : .rightStick
                let source = InputSource(deviceID: controller.id, input: input)
                var output: [ButtonMapping] = []
                gestures.output = { mapping, pressed in if pressed { output.append(mapping) } }
                gestures.handle(source, pressed: true, mapping: profile.mapping)
                gestures.handle(source, pressed: false, mapping: profile.mapping)
                clock.advance(0.1)
                gestures.handle(source, pressed: true, mapping: profile.mapping)
                gestures.handle(source, pressed: false, mapping: profile.mapping)
                clock.advance(1)
                #expect(output.count == 1)
                let emitted = try #require(output.first)
                #expect(emitted.action == .macro)
                let macro = try #require(config.macros.first { $0.id == emitted.macroID })
                #expect(macro.name.contains("新建"))
            }
        }
    }
}
