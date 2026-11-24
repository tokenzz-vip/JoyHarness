import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct ShortcutReferenceTests {
    @Test func controllerGestureTogglesOnlyOnFreshTriggers() throws {
        let suite = "JoyHarness.ShortcutReference.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let clock = TestClock()
        let engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        let model = DashboardModel(defaults: defaults, preview: true, transports: [], inputEngine: engine)
        let controller = JoyConProfile.all[1]
        model.selectControllerProfile(controller)
        model.saveMappings([.long: .init(action: .toggleShortcutReference)], input: .a)
        func report(_ buttons: Set<ControllerInput>, deviceID: String = "selected") {
            engine.receive(id: deviceID, profile: controller, snapshot: .init(
                buttons: buttons, stick: .neutral, battery: 75, charging: false))
        }
        engine.selectDevice("selected")
        report([])
        var requests = 0
        model.onToggleShortcutReference = { requests += 1 }

        report([.a], deviceID: "other")
        clock.advance(1)
        #expect(requests == 0)
        report([.a])
        clock.advance(0.56)
        #expect(requests == 1)
        report([.a])
        clock.advance(1)
        report([])
        #expect(requests == 1)

        report([.a])
        clock.advance(0.56)
        report([])
        #expect(requests == 2)
    }

    @Test func referenceUsesRunningProfileAndRuntimeOverrides() throws {
        let suite = "JoyHarness.ShortcutReference.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let engine = InputEngine()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [], inputEngine: engine)
        model.selectControllerProfile(JoyConProfile.all[1])
        let active = model.defaultProfile
        let editing = try #require(model.configuration.profiles.first { $0.id != active.id })
        model.saveMappings([.single: .init(action: .copy), .double: .init(action: .paste)], input: .a)
        model.selectProfile(editing.id)
        model.saveMappings([.single: .init(action: .backspace)], input: .a)
        model.saveMappings([.long: .init(action: .toggleShortcutReference)], input: .home)
        model.setMouseButton(.a, for: .left)

        #expect(model.activeProfile.id == active.id)
        #expect(model.activeMapping(for: .a, gesture: .single).action == .copy)
        #expect(model.mappingForEditing(.a, gesture: .single).action == .backspace)
        #expect(model.activeMapping(for: .home, gesture: .long).action == .toggleShortcutReference)
        #expect(model.activeMapping(for: .rightSR, gesture: .single).action == .voiceShortcut)
        engine.cycleStickMode(for: .right)
        #expect(model.activeMapping(for: .a, gesture: .single).action == .mouseLeft)
        #expect(model.activeMapping(for: .a, gesture: .double).action == .disabled)
        #expect(model.activeMapping(for: .rightStickUp, gesture: .single).action == .arrowUp)
    }
}
