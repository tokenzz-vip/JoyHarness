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
            #expect(model.voiceInput == (profile.side == .left ? .leftSL : .rightSR))
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

    @Test func voiceMigrationPreservesExistingGlobalAndMouseAssignments() throws {
        var config = Configuration()
        let left = JoyConProfile.all[0], right = JoyConProfile.all[1]
        config.globalButtons[left.id]?.append(.init(input: .leftSL, actions: [.double: .init(action: .copy)]))
        config.mouseButtons[right.id] = .init(left: .rightSR)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        legacy.removeValue(forKey: "voiceButtons")
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
        #expect(decoded.globalButtons == config.globalButtons)
        #expect(decoded.mouseButtons == config.mouseButtons)
        #expect(decoded.voiceButtons[left.id]?.input == nil)
        #expect(decoded.voiceButtons[right.id]?.input == nil)
        #expect(decoded.voiceButtons[JoyConProfile.all[2].id]?.input == .leftSL)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func voiceOverrideHoldsImmediatelyAndReleasesWhenInputIsCancelled() throws {
        let suite = "JoyHarness.VoiceButton.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock()
        let engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        let model = DashboardModel(defaults: defaults, preview: true, transports: [], inputEngine: engine)
        let controller = JoyConProfile.all[2]
        model.selectControllerProfile(controller)
        let profileID = DefaultKeyProfiles.id(for: .chatGPT)
        model.setDefaultProfile(profileID)
        model.selectProfile(profileID)
        #expect(model.selectedProfile.mapping[.leftSL, .double].action == .macro)
        let voice = try #require(model.voiceInput)
        let neutral = JoyConSnapshot(buttons: [], stick: .neutral, battery: 75, charging: false)
        var held = neutral
        held.buttons = [voice]
        var events: [Bool] = []
        engine.output = { mapping, pressed in if mapping.voiceShortcut?.keys == [.function] { events.append(pressed) } }

        let cancellations: [() -> Void] = [
            { engine.receive(id: "selected", profile: controller, snapshot: neutral) },
            { engine.disconnect("selected") },
            { engine.selectDevice("different", baseline: held) },
            { model.setEnabled(false) },
            { model.setDefaultProfile(model.configuration.profiles[0].id) },
            { model.setVoiceInput(nil) }
        ]
        for cancel in cancellations {
            events.removeAll()
            engine.selectDevice("selected", baseline: neutral)
            engine.receive(id: "unselected", profile: controller, snapshot: held)
            #expect(events.isEmpty)
            engine.receive(id: "selected", profile: controller, snapshot: held)
            #expect(events == [true])
            clock.advance(0.7)
            #expect(events == [true])
            cancel()
            #expect(events == [true, false])
            model.setEnabled(true)
        }
        model.setDefaultProfile(profileID)
        #expect(engine.profile.mapping[voice, .double].action == .macro)
        #expect(!model.voiceInputChoices.contains(.minus))
        model.setMouseButton(voice, for: .left)
        model.setVoiceInput(voice)
        #expect(model.voiceInput == nil)
        let relaunched = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(relaunched.voiceInput == nil)
    }

    @Test func tapVoiceShortcutTogglesAndStopsBeforeAnotherButtonAction() throws {
        let suite = "JoyHarness.VoiceButton.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = InputEngine()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [], inputEngine: engine)
        let controller = JoyConProfile.all[2]
        model.selectControllerProfile(controller)
        let input = try #require(model.voiceInput)
        var button = model.voiceButton
        button.mode = .tap
        button.holdKey = .rightControl
        button.tapKeys = [.leftCommand, .rightCommand]
        #expect(!model.saveVoiceButton(button, controllerID: JoyConProfile.all[0].id))
        #expect(model.saveVoiceButton(button, controllerID: controller.id))
        var events: [String] = []
        engine.output = { events.append("\($0.action.rawValue):\($1)") }
        func snapshot(_ buttons: Set<ControllerInput> = []) -> JoyConSnapshot {
            .init(buttons: buttons, stick: .neutral, battery: 75, charging: false)
        }
        func report(_ buttons: Set<ControllerInput> = []) {
            engine.receive(id: "selected", profile: controller, snapshot: snapshot(buttons))
        }
        engine.selectDevice("selected", baseline: snapshot())
        report([input])
        report()
        #expect(events == ["voiceShortcut:true", "voiceShortcut:false"])
        report([input])
        report()
        #expect(events.count == 4)

        events.removeAll()
        report([input])
        report([.up])
        #expect(events == ["voiceShortcut:true", "voiceShortcut:false",
                           "voiceShortcut:true", "voiceShortcut:false", "arrowUp:true"])
        report()
        report([input])
        engine.disconnect("unselected")
        #expect(events.count == 8)
        engine.disconnect("selected")
        #expect(events.suffix(2) == ["voiceShortcut:true", "voiceShortcut:false"])
        #expect(events.count == 10)

        model.setVoiceInput(.leftSR)
        button.input = .leftSR
        let restored = DashboardModel(defaults: defaults, preview: true, transports: [])
        restored.selectControllerProfile(controller)
        #expect(restored.voiceButton == button)
        let decoded = try JSONDecoder().decode(VoiceButton.self, from: Data(#"{"input":"leftSL"}"#.utf8))
        #expect(decoded == VoiceButton(input: .leftSL))
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
