import Foundation
import Testing
@testable import JoyHarness

@MainActor
private final class StickTestTransport: ControllerTransport {
    var onDevice: ((ConnectedJoyCon) -> Void)?
    var onInput: ((String, JoyConProfile, JoyConSnapshot) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    func start() {}
    func stop() {}
}

struct StickDirectionTests {
    @Test func deadzoneCalibrationDiagonalsAndHysteresis() {
        #expect(StickPosition.neutral.directions(side: .left, deadzone: 0.18).isEmpty)
        #expect(StickPosition(x: 4095, y: 4095).directions(side: .left, deadzone: 0.18) == [.leftStickUp, .leftStickRight])
        #expect(StickPosition(x: 0, y: 0).directions(side: .right, deadzone: 0.18) == [.rightStickDown, .rightStickLeft])
        let center = StickCenter(x: 2600, y: 1700)
        #expect(StickPosition(x: 2600, y: 1700).directions(side: .left, center: center, deadzone: 0.18).isEmpty)
        #expect(StickPosition(x: 2600, y: 4095).directions(side: .right, center: center, deadzone: 0.18) == [.rightStickUp])
        let boundary = StickPosition(x: 2850, y: 2048)
        #expect(boundary.directions(side: .left, deadzone: 0.18).isEmpty)
        #expect(boundary.directions(side: .left, deadzone: 0.18, previous: [.leftStickRight]) == [.leftStickRight])
        #expect(StickPosition(x: 2670, y: 2048).directions(side: .left, deadzone: 0.18, previous: [.leftStickRight]).isEmpty)
    }

    @Test func oldProfilesDiscardInitialModesAndKeepDirectionMappings() throws {
        var config = Configuration()
        config.profiles[0].mapping[.leftStickUp] = .init(action: .copy)
        let encoded = try JSONEncoder().encode(config)
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var profiles = try #require(legacy["profiles"] as? [[String: Any]])
        for oldMode in ["pointer", "scroll", "arrows", "mapped", "disabled"] {
            profiles[0]["leftStick"] = oldMode
            profiles[0]["rightStick"] = oldMode
            legacy["profiles"] = profiles
            let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: legacy))
            #expect(try decoded.validated() == config)
        }
        config.profiles[0].mapping.buttons.removeAll()
        for side in [JoyConSide.left, .right] {
            for (input, action) in zip(ControllerInput.stickDirections(for: side), [RemoteAction.arrowUp, .arrowDown, .arrowLeft, .arrowRight]) {
                #expect(config.profiles[0].mapping[input].action == action)
                #expect(config.profiles[0].mapping[input, .double].action == .disabled)
            }
        }
        config.profiles[0].mapping[.leftStickUp] = .init(action: .disabled)
        config.profiles[0].mapping[.leftStickDown, .long] = .init(action: .copy)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)).validated() == config)
    }
}

@MainActor
struct StickMappingRuntimeTests {
    private func snapshot(_ x: Int = 2048, _ y: Int = 2048, buttons: Set<ControllerInput> = []) -> JoyConSnapshot {
        .init(buttons: buttons, stick: .init(x: x, y: y), battery: 75, charging: false)
    }

    @Test func pointerModeAccumulatesSmallMovementsAndStopsAtCenter() {
        for controller in JoyConProfile.all {
            let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
            engine.selectDevice("one", baseline: snapshot())
            engine.cycleStickMode(for: controller.side)
            var moves: [CGPoint] = []
            engine.pointer = { moves.append(CGPoint(x: $0, y: $1)) }
            engine.receive(id: "one", profile: controller, snapshot: snapshot(2480))
            engine.tick()
            #expect(moves.isEmpty)
            engine.tick()
            #expect(moves == [CGPoint(x: 1, y: 0)])
            engine.receive(id: "one", profile: controller, snapshot: snapshot())
            engine.tick()
            #expect(moves.count == 1)
            engine.receive(id: "one", profile: controller, snapshot: snapshot(4095, 4095))
            engine.tick()
            #expect(moves.last == CGPoint(x: 9, y: -9))
        }
    }

    @Test func mouseButtonBindingsOverridePhysicalActionsOnlyInPointerMode() {
        let engine = InputEngine()
        var profile = KeyProfile()
        profile.mapping[.a] = .init(action: .enter)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:],
                         mouseButtons: .init(left: .a, right: .b))
        #expect(engine.mouseButtonBindings == .init(left: .a, right: .b))
        engine.selectDevice("one", baseline: snapshot())
        var events: [String] = []
        engine.output = { mapping, pressed in events.append("\(mapping.action.rawValue):\(pressed)") }
        let controller = JoyConProfile.all[1]
        engine.cycleStickMode(for: .right)
        engine.receive(id: "one", profile: controller, snapshot: snapshot(buttons: [.a]))
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        #expect(events == ["mouseLeft:true", "mouseLeft:false"])

        events.removeAll()
        engine.receive(id: "one", profile: controller, snapshot: snapshot(buttons: [.b]))
        engine.cycleStickMode(for: .right)
        #expect(events == ["mouseRight:true", "mouseRight:false"])
        engine.receive(id: "one", profile: controller, snapshot: snapshot(buttons: [.b]))
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        #expect(events == ["mouseRight:true", "mouseRight:false"])
        events.removeAll()
        engine.receive(id: "one", profile: controller, snapshot: snapshot(buttons: [.a]))
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        #expect(events == ["enter:true", "enter:false"])
    }

    @Test func fourDirectionsAreIndependentOnEveryControllerAndDoNotMovePointer() {
        for controller in JoyConProfile.all {
            let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
            var profile = KeyProfile()
            let directions = ControllerInput.stickDirections(for: controller.side)
            let actions: [RemoteAction] = [.copy, .paste, .enter, .escape]
            for (input, action) in zip(directions, actions) { profile.mapping[input] = .init(action: action) }
            engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
            engine.selectDevice("one", baseline: snapshot())
            var events: [String] = [], counted: [ControllerInput] = [], analogEvents = 0
            engine.output = { events.append("\($0.action.rawValue):\($1)") }
            engine.buttonPressed = { counted.append($0) }
            engine.pointer = { _, _ in analogEvents += 1 }
            let positions = [snapshot(2048, 4095), snapshot(2048, 0), snapshot(0, 2048), snapshot(4095, 2048)]
            for (position, action) in zip(positions, actions) {
                events = []
                engine.receive(id: "one", profile: controller, snapshot: position)
                engine.receive(id: "one", profile: controller, snapshot: position)
                engine.tick()
                #expect(events == ["\(action.rawValue):true"])
                engine.receive(id: "one", profile: controller, snapshot: snapshot())
                #expect(events == ["\(action.rawValue):true", "\(action.rawValue):false"])
            }
            #expect(counted == directions)
            #expect(analogEvents == 0)
        }
    }

    @Test func doubleAndLongDirectionsUseGestureRecognition() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        var profile = KeyProfile()
        profile.mapping[.leftStickUp, .double] = .init(action: .copy)
        profile.mapping[.leftStickDown, .long] = .init(action: .paste)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice("one", baseline: snapshot())
        var events: [RemoteAction] = []; engine.output = { if $1 { events.append($0.action) } }
        let controller = JoyConProfile.all[0]
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 4095))
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        clock.advance(0.1)
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 4095))
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        clock.advance(0.4); #expect(events == [.copy])
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 0))
        clock.advance(0.3)
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 0))
        engine.tick(); clock.advance(0.26)
        #expect(events == [.copy, .paste])
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        #expect(events == [.copy, .paste])
    }

    @Test func staleDisconnectPauseAndProfileChangeReleaseDirectionHolds() {
        for stop in ["stale", "disconnect", "pause", "profile", "cancel", "selection"] {
            let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
            var profile = KeyProfile()
            engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
            engine.selectDevice("one", baseline: snapshot())
            var events: [String] = []; engine.output = { events.append("\($0.action.rawValue):\($1)") }
            engine.receive(id: "one", profile: JoyConProfile.all[0], snapshot: snapshot(2048, 4095))
            switch stop {
            case "stale": clock.advance(0.51); engine.tick()
            case "disconnect": engine.disconnect("one")
            case "pause": engine.setEnabled(false)
            case "profile": engine.configure(profile: KeyProfile(), deadzone: 0.18, speed: 14, centers: [:])
            case "selection": engine.selectDevice("two", baseline: snapshot())
            default: engine.cancel()
            }
            #expect(events == ["arrowUp:true", "arrowUp:false"])
        }
    }

    @Test func staleInputCancelsPendingLongAndPhysicalKeysShareHoldCounts() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        var profile = KeyProfile()
        profile.mapping[.leftStickDown, .long] = .init(action: .copy)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice("one", baseline: snapshot())
        var events: [String] = []; engine.output = { events.append("\($0.action.rawValue):\($1)") }
        let controller = JoyConProfile.all[0]
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 0))
        clock.advance(0.51); engine.tick(); clock.advance(1)
        #expect(events.isEmpty)
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 4095, buttons: [.up]))
        #expect(events == ["arrowUp:true"])
        engine.receive(id: "one", profile: controller, snapshot: snapshot(2048, 4095))
        #expect(events.count == 1)
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        #expect(events == ["arrowUp:true", "arrowUp:false"])
    }

    @Test func selectionRequiresNeutralAndOtherStickModesIgnoreDirectionMappings() {
        for mode in StickMode.allCases {
            let engine = InputEngine()
            var profile = KeyProfile()
            profile.mapping[.leftStickRight] = .init(action: .copy)
            engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
            engine.selectDevice("one", baseline: snapshot(4095, 2048))
            if mode == .pointer { engine.cycleStickMode(for: .left) }
            var actions: [RemoteAction] = []; engine.output = { if $1 { actions.append($0.action) } }
            engine.receive(id: "one", profile: JoyConProfile.all[0], snapshot: snapshot(4095, 2048))
            #expect(actions.isEmpty)
            engine.receive(id: "one", profile: JoyConProfile.all[0], snapshot: snapshot())
            engine.receive(id: "one", profile: JoyConProfile.all[0], snapshot: snapshot(4095, 2048))
            #expect(actions == (mode == .mapped ? [.copy] : []))
        }
    }

    @Test func directionModeRecoverySurvivesProfileSwitchWhilePaused() {
        let engine = InputEngine()
        var profile = KeyProfile()
        profile.mapping[.leftStickUp] = .init(action: .toggleMode)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice("one", baseline: snapshot())
        engine.setEnabled(false)
        engine.configure(profile: KeyProfile(), deadzone: 0.18, speed: 14, centers: [:])
        var actions: [RemoteAction] = []; engine.output = { if $1 { actions.append($0.action) } }
        engine.receive(id: "one", profile: JoyConProfile.all[0], snapshot: snapshot(2048, 4095))
        #expect(actions == [.toggleMode])
    }

    @Test func editingDirectionsPreservesModesAndPersists() {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = StickTestTransport(), model = DashboardModel(defaults: defaults, preview: true, transports: [transport])
        model.saveMapping(.init(action: .copy), input: .leftStickUp, gesture: .double)
        #expect(model.currentStickMode(for: .left) == .mapped)
        #expect(model.currentStickMode(for: .right) == .mapped)
        let restored = DashboardModel(defaults: defaults, preview: true)
        #expect(restored.selectedProfile == model.selectedProfile)
        transport.onDevice?(.init(id: "one", profile: JoyConProfile.all[0], ready: true))
        transport.onInput?("one", JoyConProfile.all[0], snapshot())
        transport.onInput?("one", JoyConProfile.all[0], snapshot(4095, 2048))
        #expect(model.pressed.contains(.leftStickRight))
        transport.onInput?("one", JoyConProfile.all[0], snapshot())
        #expect(!model.pressed.contains(.leftStickRight))
    }
}


@MainActor
struct StickModeSwitchTests {
    private func snapshot(_ buttons: Set<ControllerInput> = [], y: Int = 2048) -> JoyConSnapshot {
        .init(buttons: buttons, stick: .init(x: 2048, y: y), battery: 75, charging: false)
    }

    @Test func boundFunctionsCycleEveryModeIndependentlyAndPersistBindings() {
        for controller in JoyConProfile.all {
            let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let transport = StickTestTransport()
            let model = DashboardModel(defaults: defaults, preview: true, transports: [transport])
            let side = controller.side, input: ControllerInput = side == .left ? .l : .r
            let action: RemoteAction = side == .left ? .cycleLeftStickMode : .cycleRightStickMode
            model.saveMapping(.init(action: action), input: input, gesture: .single)
            transport.onDevice?(.init(id: "one", profile: controller, ready: true))
            model.selectDevice("one")
            transport.onInput?("one", controller, snapshot())
            #expect(model.currentStickMode(for: side) == .mapped)
            for expected in [StickMode.pointer, .mapped] {
                transport.onInput?("one", controller, snapshot([input]))
                #expect(model.currentStickMode(for: side) == expected)
                transport.onInput?("one", controller, snapshot([input]))
                #expect(model.currentStickMode(for: side) == expected)
                transport.onInput?("one", controller, snapshot())
                #expect(model.currentStickMode(for: side == .left ? .right : .left) == expected)
            }
            let restored = DashboardModel(defaults: defaults, preview: true)
            #expect(restored.selectedProfile.mapping[input].action == action)
            #expect(restored.currentStickMode(for: side) == .mapped)
        }
    }

    @Test func switchingReleasesDirectionsAndWaitsForNeutralWithoutRepeating() {
        let engine = InputEngine()
        var profile = KeyProfile()
        profile.mapping[.l] = .init(action: .cycleLeftStickMode)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice("one", baseline: snapshot())
        var events: [String] = [], pointerMoves = 0
        engine.output = { mapping, pressed in
            if mapping.action == .cycleLeftStickMode {
                if pressed { engine.cycleStickMode(for: .left) }
            } else { events.append("\(mapping.action.rawValue):\(pressed)") }
        }
        engine.pointer = { x, y in if x != 0 || y != 0 { pointerMoves += 1 } }
        let controller = JoyConProfile.all[0]
        engine.receive(id: "one", profile: controller, snapshot: snapshot(y: 4095))
        engine.tick()
        #expect(events == ["arrowUp:true"])
        engine.receive(id: "one", profile: controller, snapshot: snapshot([.l], y: 4095))
        #expect(events == ["arrowUp:true", "arrowUp:false"])
        engine.receive(id: "one", profile: controller, snapshot: snapshot([.l], y: 4095))
        #expect(engine.stickMode(for: .left) == .pointer)
        engine.tick()
        engine.receive(id: "one", profile: controller, snapshot: snapshot(y: 4095)); engine.tick()
        #expect(pointerMoves == 0)
        #expect(events == ["arrowUp:true", "arrowUp:false"])
        engine.receive(id: "one", profile: controller, snapshot: snapshot())
        engine.receive(id: "one", profile: controller, snapshot: snapshot(y: 4095)); engine.tick()
        #expect(pointerMoves == 1)
    }

    @Test func doubleAndLongSwitchesFireOnceAndPendingDirectionsAreCancelled() {
        for gesture in [Gesture.double, .long] {
            let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
            var profile = KeyProfile()
            profile.mapping[.l, gesture] = .init(action: .cycleLeftStickMode)
            profile.mapping[.leftStickUp, .long] = .init(action: .copy)
            engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
            engine.selectDevice("one", baseline: snapshot())
            var switches = 0, copies = 0
            engine.output = { mapping, pressed in
                if pressed, mapping.action == .cycleLeftStickMode { switches += 1; engine.cycleStickMode(for: .left) }
                if pressed, mapping.action == .copy { copies += 1 }
            }
            let controller = JoyConProfile.all[0]
            engine.receive(id: "one", profile: controller, snapshot: snapshot([.l]))
            if gesture == .double {
                engine.receive(id: "one", profile: controller, snapshot: snapshot())
                clock.advance(0.1)
                engine.receive(id: "one", profile: controller, snapshot: snapshot([.l], y: 4095))
                engine.receive(id: "one", profile: controller, snapshot: snapshot(y: 4095))
            } else {
                clock.advance(0.2)
                engine.receive(id: "one", profile: controller, snapshot: snapshot([.l], y: 4095))
                clock.advance(0.4)
            }
            clock.advance(1)
            #expect(switches == 1); #expect(copies == 0)
            #expect(engine.stickMode(for: .left) == .pointer)
        }
    }

    @Test func switchingOnPressOrReleaseSkipsDirectionsFromTheSameReport() {
        for deferred in [false, true] {
            let engine = InputEngine()
            var profile = KeyProfile()
            profile.mapping[.l] = .init(action: .cycleLeftStickMode)
            if deferred { profile.mapping[.l, .long] = .init(action: .copy) }
            engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
            engine.selectDevice("one", baseline: snapshot())
            var directions = 0
            engine.output = { mapping, pressed in
                if pressed, mapping.action == .cycleLeftStickMode { engine.cycleStickMode(for: .left) }
                if pressed, mapping.action == .arrowUp { directions += 1 }
            }
            let controller = JoyConProfile.all[0]
            if deferred {
                engine.receive(id: "one", profile: controller, snapshot: snapshot([.l]))
                engine.receive(id: "one", profile: controller, snapshot: snapshot(y: 4095))
            } else {
                engine.receive(id: "one", profile: controller, snapshot: snapshot([.l], y: 4095))
            }
            #expect(engine.stickMode(for: .left) == .pointer)
            #expect(directions == 0)
        }
    }

    @Test func modeSwitchRespectsPauseAndResetsWithProfileOrSelection() {
        let engine = InputEngine(), profile = KeyProfile()
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.cycleStickMode(for: .left)
        #expect(engine.stickMode(for: .left) == .pointer)
        engine.setEnabled(false); engine.cycleStickMode(for: .left)
        #expect(engine.stickMode(for: .left) == .pointer)
        engine.setEnabled(true)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        #expect(engine.stickMode(for: .left) == .pointer)
        engine.configure(profile: KeyProfile(name: "另一套方案"), deadzone: 0.18, speed: 14, centers: [:])
        #expect(engine.stickMode(for: .left) == .mapped)
        engine.cycleStickMode(for: .right)
        #expect(engine.stickMode(for: .right) == .pointer)
        engine.selectDevice("two", baseline: snapshot())
        #expect(engine.stickMode(for: .right) == .mapped)
    }

    @Test func switchBindingsRoundTripAndCannotRunInMacros() throws {
        var config = Configuration()
        config.profiles[0].mapping[.l, .double] = .init(action: .cycleLeftStickMode)
        config.profiles[0].mapping[.r, .long] = .init(action: .cycleRightStickMode)
        #expect(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)).validated() == config)
        for action in [RemoteAction.cycleLeftStickMode, .cycleRightStickMode] {
            config.macros = [.init(steps: [.init(mapping: .init(action: action))])]
            #expect(throws: (any Error).self) { try config.validated() }
        }
    }
}
