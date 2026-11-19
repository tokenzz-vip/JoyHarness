import Foundation
import Testing
@testable import JoyHarness

struct HarnessTests {
    @Test func builtInsMatchRcHarnessAndRecognizeApplications() throws {
        let expected = [
            ("ChatGPT", "com.openai.codex"), ("Claude", "com.anthropic.claudefordesktop"),
            ("Cursor", "com.todesktop.230313mzl4w4u92"), ("DeepSeek", "com.deepseek.dsh"),
            ("WorkBuddy", "com.tencent.workbuddy.mac"), ("OpenCode", "ai.opencode.desktop"),
        ]
        let config = try Configuration().addingBuiltInHarnesses().validated()
        #expect(config.harnesses.map(\.name) == expected.map(\.0))
        for (binding, application) in zip(config.harnesses, expected) {
            #expect(binding.bundleID == application.1)
            #expect(binding.isBuiltIn)
            #expect(binding.matches(bundleID: application.1.uppercased()))
            #expect(!binding.matches(bundleID: "other.app"))
            #expect(!binding.matches(bundleID: nil))
            #expect(binding.profileID == config.profiles[0].id)
        }
    }

    @Test func upgradeAndImportPreserveBindingsAndAreIdempotent() throws {
        var old = Configuration()
        old.profiles.append(.init(name: "我的方案"))
        old.defaultProfileID = old.profiles[1].id
        old.profiles[1].mapping[.a] = .init(action: .copy)
        old.harnesses = [
            .init(applicationPath: "/custom/WorkBuddy.app", bundleID: "COM.WORKBUDDY.WORKBUDDY",
                  profileID: old.profiles[1].id, enabled: false),
            .init(applicationPath: "/custom/Browser.app", bundleID: "my.browser", profileID: old.profiles[0].id),
        ]
        let upgraded = try old.addingBuiltInHarnesses().validated()
        #expect(Array(upgraded.harnesses.prefix(2)) == old.harnesses)
        #expect(upgraded.profiles == old.profiles)
        #expect(upgraded.harnesses.count == 7)
        #expect(upgraded.harnesses.dropFirst(2).allSatisfy { $0.profileID == old.defaultProfileID })
        #expect(upgraded.addingBuiltInHarnesses() == upgraded)
        let imported = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(old))
            .validated().addingBuiltInHarnesses().validated()
        // Newly introduced entries get fresh UUIDs; existing entries retain theirs.
        #expect(Array(imported.harnesses.prefix(2)) == old.harnesses)
        #expect(imported.harnesses.map(\.bundleID) == upgraded.harnesses.map(\.bundleID))
        #expect(imported.profiles == old.profiles)
    }

    @Test func workBuddyAliasesResolveAndRejectDuplicateBindings() throws {
        var config = Configuration().addingBuiltInHarnesses()
        let binding = try #require(config.harnesses.first { $0.name == "WorkBuddy" })
        let legacyURL = URL(fileURLWithPath: "/custom/WorkBuddy.app")
        var attempted: [String] = []
        let resolved = binding.installedApplicationURL { identifier in
            attempted.append(identifier)
            return identifier == "com.workbuddy.workbuddy" ? legacyURL : nil
        }
        #expect(resolved == legacyURL)
        #expect(attempted == ["com.tencent.workbuddy.mac", "com.workbuddy.workbuddy"])
        #expect(binding.matches(bundleID: "COM.WORKBUDDY.WORKBUDDY"))
        config.harnesses.append(.init(applicationPath: legacyURL.path, bundleID: "com.workbuddy.workbuddy",
                                     profileID: config.profiles[0].id))
        #expect(throws: Error.self) { try config.validated() }
    }

    @Test func maximumExistingCustomBindingsCanGainBuiltIns() throws {
        var config = Configuration()
        config.harnesses = (0..<500).map {
            .init(applicationPath: "/custom/App\($0).app", bundleID: "custom.app\($0)", profileID: config.profiles[0].id)
        }
        #expect(try config.addingBuiltInHarnesses().validated().harnesses.count == 506)
    }

    @Test func chatGPTIsTheOnlyBuiltInIdentityForItsApplication() throws {
        let app = HarnessApplication.chatGPT
        #expect(HarnessApplication.defaults.filter { $0.matches(bundleID: "com.openai.codex") } == [app])
        #expect(HarnessApplication.defaults.allSatisfy { $0.id != "codex" })
        #expect(MacroTag.all.contains(.init(id: "chatgpt", name: "ChatGPT")))
        #expect(MacroTag.all.allSatisfy { $0.id != "codex" })
        #expect(RemoteAction(rawValue: "focusCodex") == nil)
        let action = try JSONDecoder().decode(RemoteAction.self, from: Data("\"focusChatGPT\"".utf8))
        #expect(action.harnessFocusTarget?.rawValue == app.id)
    }
}

@MainActor
struct HarnessModelTests {
    @Test func installedPresetsAreReplacedInPlaceWithChatGPT() throws {
        let suite = "JoyHarness.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = Configuration().addingBuiltInMacros().addingBuiltInProfiles().addingBuiltInHarnesses()
        original.macroPresetsVersion = 6
        original.profilePresetsVersion = 1
        original.harnesses[0].applicationPath = "/Applications/Codex.app"
        original.harnesses[0].enabled = false
        original.profiles[1].name = "Codex 按键方案"
        original.profiles[1].mapping[.a] = .init(action: .copy)
        original.macros[0].name = "Codex-新建会话"
        original.macros[0].tagIDs = ["codex"]
        original.macros[0].steps[0].delay = 0.5
        SettingsStorage.save(original, "configuration.v1", defaults: defaults)

        let current = DashboardModel(defaults: defaults, preview: true).configuration
        #expect(current.harnesses.count == original.harnesses.count)
        #expect(current.harnesses[0].name == "ChatGPT")
        #expect(current.harnesses[0].applicationPath == "/Applications/ChatGPT.app")
        #expect(current.harnesses[0].profileID == original.harnesses[0].profileID)
        #expect(!current.harnesses[0].enabled)
        #expect(current.profiles[1].name == "ChatGPT 按键方案")
        #expect(current.profiles[1].mapping == original.profiles[1].mapping)
        #expect(current.macros[0].name == "ChatGPT-新建会话")
        #expect(current.macros[0].tagIDs == ["chatgpt"])
        #expect(current.macros[0].steps == original.macros[0].steps)
        #expect(DashboardModel(defaults: defaults, preview: true).configuration == current)
    }

    @Test func upgradePersistsAndDeletingProfileKeepsBuiltInsValid() throws {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = Configuration()
        old.profiles[0].mapping[.a] = .init(action: .paste)
        SettingsStorage.save(old, "configuration.v1", defaults: defaults)
        let model = DashboardModel(defaults: defaults, preview: true)
        #expect(model.configuration.harnesses.count == 6)
        #expect(Array(model.configuration.profiles.prefix(old.profiles.count)) == old.profiles)
        #expect(model.configuration.profiles.count == 7)
        let restored = DashboardModel(defaults: defaults, preview: true)
        #expect(restored.configuration == model.configuration)
        model.configuration.harnesses[1].enabled = false
        model.duplicateProfile()
        model.deleteProfile(old.profiles[0].id)
        #expect(model.configuration.harnesses.count == 6)
        #expect(!model.configuration.harnesses[1].enabled)
        #expect(model.configuration.harnesses.allSatisfy { DefaultKeyProfiles.presetIDs.contains($0.profileID) })
        #expect(try model.configuration.validated() == model.configuration)
    }
}
