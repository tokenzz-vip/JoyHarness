import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct GlobalButtonTests {
    @Test func requiredRowAndUniquePhysicalChoicesAreScopedToControllerModel() throws {
        let suite = "JoyHarness.GlobalButtons.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true, transports: [])
        for profile in JoyConProfile.all {
            model.selectControllerProfile(profile)
            #expect(model.globalButtons.compactMap(\.input) == (profile.side == .left ? [.minus, .capture] : [.plus, .home]))
        }

        model.selectControllerProfile(JoyConProfile.all[1])
        let required = try #require(model.globalButtons.first)
        let optional = model.globalButtons[1]
        model.setGlobalInput(nil, for: required.id)
        model.setGlobalInput(.home, for: required.id)
        model.setGlobalInput(.c, for: required.id)
        model.removeGlobalButton(required.id)
        #expect(model.globalButtons == [required, optional])

        model.setGlobalInput(nil, for: optional.id)
        model.setGlobalInput(.home, for: required.id)
        model.removeGlobalButton(optional.id)
        model.addGlobalButton()
        let extra = model.globalButtons[1].id
        #expect(!model.globalInputChoices(for: extra).contains(.home))
        model.setGlobalInput(.a, for: extra)
        #expect(model.globalButtons.compactMap(\.input) == [.home, .a])

        let relaunched = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(relaunched.globalButtons == model.globalButtons)
        relaunched.selectControllerProfile(JoyConProfile.all[3])
        #expect(relaunched.globalButtons.compactMap(\.input) == [.plus, .home])
    }

    @Test func globalGesturesOverrideEveryProfileAndRemovingTheRowRestoresItsBindings() throws {
        let suite = "JoyHarness.GlobalButtons.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = InputEngine()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [], inputEngine: engine)
        model.selectControllerProfile(JoyConProfile.all[1])
        let first = model.defaultProfile
        let second = try #require(model.configuration.profiles.first { $0.id != first.id })
        model.selectProfile(second.id)
        model.saveMappings([.single: .init(action: .copy), .double: .init(action: .paste)], input: .home)

        #expect(model.selectedProfile.mapping[.home] == second.mapping[.home])
        #expect(engine.profile.mapping[.home].action == .copy)
        #expect(engine.profile.mapping[.home, .double].action == .paste)
        model.setDefaultProfile(second.id)
        model.selectProfile(first.id)
        #expect(model.mappingForEditing(.home, gesture: .single).action == .copy)
        #expect(engine.profile.mapping[.home, .double].action == .paste)

        model.removeGlobalButton(model.globalButtons[1].id)
        #expect(model.mappingForEditing(.home, gesture: .single) == first.mapping[.home])
        #expect(engine.profile.mapping[.home] == second.mapping[.home])
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(model.configuration))
        #expect(try decoded.validated() == model.configuration)
    }

    @Test func mouseButtonChoicesExcludeSticksGlobalsAndDuplicateSelection() throws {
        let suite = "JoyHarness.MouseButtons.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true, transports: [])
        model.selectControllerProfile(JoyConProfile.all[0])
        let choices = model.mouseButtonChoices(for: .left)
        #expect(!choices.contains(.leftStick))
        #expect(!choices.contains(.minus))
        #expect(!choices.contains(.capture))
        model.setMouseButton(.l, for: .left)
        model.setMouseButton(.zl, for: .right)
        #expect(model.mouseButtonBindings == .init(left: .l, right: .zl))
        #expect(!model.mouseButtonChoices(for: .right).contains(.l))
        let restored = DashboardModel(defaults: defaults, preview: true, transports: [])
        restored.selectControllerProfile(JoyConProfile.all[0])
        #expect(restored.mouseButtonBindings == .init(left: .l, right: .zl))
    }

    @Test func legacyBackupUsesSavedDefaultProfileMappingsToSeedGlobals() throws {
        var config = Configuration()
        var custom = KeyProfile(name: "自定义方案")
        custom.mapping[.minus, .long] = .init(action: .copy)
        config.profiles.append(custom)
        config.defaultProfileID = custom.id
        let json = try JSONEncoder().encode(config)
        var legacy = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        legacy.removeValue(forKey: "globalButtons")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(try decoded.validated().profiles == config.profiles)
        #expect(decoded.globalButtons["joycon-1-left"]?.first?.actions[.long]?.action == .copy)
        #expect(decoded.globalButtons["joycon-2-left"]?.first?.actions[.long]?.action == .copy)
    }
}

extension GlobalButtonTests {
    @Test func defaultAndMigratedVolumeKeysAllowApplicationGestures() throws {
        var config = Configuration().addingBuiltInMacros().addingBuiltInProfiles()
        for controller in JoyConProfile.all {
            for gesture in [Gesture.double, .long] {
                config.globalButtons[controller.id]?[0].actions[gesture] = .init()
            }
        }
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        json.removeValue(forKey: "globalGestureOverrides")
        let migrated = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
        for controller in JoyConProfile.all {
            let key: ControllerInput = controller.side == .left ? .minus : .plus
            let profile = try #require(migrated.profiles.first { $0.id == DefaultKeyProfiles.id(for: .chatGPT) })
            let effective = migrated.effectiveMapping(profile.mapping, for: controller)
            #expect(effective[key, .double].action == .macro)
            #expect(effective[key, .long].action == .macro)
            #expect(effective[key].action == (key == .minus ? .volumeDown : .volumeUp))
        }
        // A user can explicitly disable a gesture after migration.
        let saved = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(saved.globalButtons == config.globalButtons)
    }
}
