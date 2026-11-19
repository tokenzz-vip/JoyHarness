import Foundation
import Testing
@testable import JoyHarness

@MainActor
final class TestClock {
    var time = 0.0
    private var pending: [(Double, Int, DispatchWorkItem)] = []
    private var counter = 0
    func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: block); counter += 1
        pending.append((time + delay, counter, item)); return item
    }
    func advance(_ seconds: Double) {
        let target = time + seconds
        while let next = pending.filter({ $0.0 <= target }).min(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
            pending.removeAll { $0.1 == next.1 }; time = next.0
            if !next.2.isCancelled { next.2.perform() }
        }
        time = target
    }
}

@MainActor
struct RuntimeTests {
    @Test func commandsOnlyAdvanceAfterMatchingAck() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var writes: [[UInt8]] = []; var complete = false
        queue.write = { writes.append($0); return true }; queue.completed = { complete = true }
        queue.start([.ble(3, 1), .ble(4, 2)])
        queue.reply(command: 9, subcommand: 1, success: true); clock.advance(0.02)
        #expect(writes.count == 1)
        queue.reply(command: 3, subcommand: 1, success: true)
        // An unsolicited reply for a command not yet written must be ignored.
        queue.reply(command: 4, subcommand: 2, success: true); clock.advance(0.02)
        #expect(writes.count == 2); #expect(!complete)
        queue.reply(command: 4, subcommand: 2, success: true); clock.advance(0.02)
        #expect(complete); #expect(!queue.running)
        clock.advance(10); #expect(writes.count == 2)
    }
    @Test func retriesAreBounded() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var writes = 0, failures = 0
        queue.write = { _ in writes += 1; return true }; queue.failed = { _ in failures += 1 }
        queue.start([.ble(3, 1)]); clock.advance(20)
        #expect(writes == 3); #expect(failures == 1); #expect(!queue.running)
    }
    @Test func writeAndNackFailImmediately() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var failures = 0
        queue.failed = { _ in failures += 1 }; queue.write = { _ in false }; queue.start([.ble(3, 1)])
        #expect(failures == 1)
        queue.write = { _ in true }; queue.start([.ble(3, 1)])
        queue.reply(command: 3, subcommand: 1, success: false); clock.advance(5)
        #expect(failures == 2)
    }
    @Test func liveInputBarrier() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var writes = 0
        queue.write = { _ in writes += 1; return true }
        queue.start([.ble(3, 10, [9, 0, 0, 0], wait: true), .ble(0xc, 2)])
        queue.reply(command: 3, subcommand: 10, success: true); clock.advance(0.5)
        #expect(writes == 1)
        queue.inputReceived(); clock.advance(0.02); #expect(writes == 2)
    }
    @Test func liveInputTimeoutAndCancel() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var failures = 0, writes = 0
        queue.failed = { _ in failures += 1 }; queue.write = { _ in writes += 1; return true }
        queue.start([.ble(3, 10, [], wait: true)])
        queue.reply(command: 3, subcommand: 10, success: true); clock.advance(4.1)
        #expect(failures == 1)
        queue.start([.ble(3, 1)]); queue.cancel(); clock.advance(10)
        #expect(writes == 2); #expect(failures == 1)
    }
    @Test func startupCompletesWithAllAcksAndInput() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        var writes = 0, complete = false
        queue.write = { _ in writes += 1; return true }; queue.completed = { complete = true }
        queue.start(ControllerCommand.secondGenerationStartup)
        for command in ControllerCommand.secondGenerationStartup {
            if let id = command.command { queue.reply(command: id, subcommand: command.subcommand, success: true) }
            if command.waitForInput { queue.inputReceived() }
            clock.advance(0.02)
        }
        #expect(complete); #expect(writes == ControllerCommand.secondGenerationStartup.count)
    }
    @Test func gesturesCaptureOriginalMappingAndDeduplicate() {
        let clock = TestClock(), gestures = GestureController(schedule: clock.schedule)
        var events: [String] = []; gestures.output = { events.append("\($0.action.rawValue):\($1)") }
        let source = InputSource(deviceID: "one", input: .a)
        var mapping = RemoteMapping.defaults
        gestures.handle(source, pressed: true, mapping: mapping)
        gestures.handle(source, pressed: true, mapping: mapping)
        mapping[.a] = .init(action: .copy)
        gestures.handle(source, pressed: false, mapping: mapping)
        #expect(events == ["enter:true", "enter:false"])
    }
    @Test func doubleAndLongGestures() {
        let clock = TestClock(), gestures = GestureController(schedule: clock.schedule)
        var events: [RemoteAction] = []; gestures.output = { if $1 { events.append($0.action) } }
        var mapping = RemoteMapping.defaults; mapping[.a, .double] = .init(action: .copy); mapping[.a, .long] = .init(action: .paste)
        let source = InputSource(deviceID: "one", input: .a)
        gestures.handle(source, pressed: true, mapping: mapping); gestures.handle(source, pressed: false, mapping: mapping)
        clock.advance(0.15)
        gestures.handle(source, pressed: true, mapping: mapping); gestures.handle(source, pressed: false, mapping: mapping)
        clock.advance(1); #expect(events == [.copy])
        gestures.handle(source, pressed: true, mapping: mapping); clock.advance(0.56)
        gestures.handle(source, pressed: false, mapping: mapping); clock.advance(1)
        #expect(events == [.copy, .paste])
    }
    @Test func pendingSingleAndDeviceCancellation() {
        let clock = TestClock(), gestures = GestureController(schedule: clock.schedule)
        var events: [RemoteAction] = []; gestures.output = { if $1 { events.append($0.action) } }
        var mapping = RemoteMapping.defaults; mapping[.a, .double] = .init(action: .copy)
        let source = InputSource(deviceID: "one", input: .a)
        gestures.handle(source, pressed: true, mapping: mapping); gestures.handle(source, pressed: false, mapping: mapping)
        clock.advance(0.31); #expect(events == [.enter])
        gestures.handle(source, pressed: true, mapping: mapping); gestures.handle(source, pressed: false, mapping: mapping)
        gestures.cancel(deviceID: "one"); clock.advance(2); #expect(events == [.enter])
    }
    func snapshot(_ buttons: Set<ControllerInput> = [], stick: StickPosition = .neutral) -> JoyConSnapshot {
        .init(buttons: buttons, stick: stick, battery: 75, charging: false)
    }
    @Test func onlySelectedPhysicalDeviceCanHoldKeys() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule)
        var events: [String] = []; engine.output = { events.append("\($0.action.rawValue):\($1)") }
        let right = JoyConProfile.all[1]
        engine.selectDevice("first", baseline: snapshot())
        engine.receive(id: "first", profile: right, snapshot: snapshot([.a]))
        engine.receive(id: "second", profile: right, snapshot: snapshot([.a]))
        engine.disconnect("second"); #expect(events == ["enter:true"])
        engine.disconnect("first"); #expect(events == ["enter:true", "enter:false"])
    }
    @Test func modeAndProfileSwitchReleaseHeldKeys() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule)
        var events: [String] = []; engine.output = { events.append("\($0.action.rawValue):\($1)") }
        let right = JoyConProfile.all[1]
        engine.selectDevice("right", baseline: snapshot())
        engine.receive(id: "right", profile: right, snapshot: snapshot([.c]))
        engine.setEnabled(false)
        #expect(events == ["rightCommand:true", "rightCommand:false"])
        engine.receive(id: "right", profile: right, snapshot: snapshot())
        engine.receive(id: "right", profile: right, snapshot: snapshot([.a])); #expect(events.count == 2)
        engine.setEnabled(true); engine.receive(id: "right", profile: right, snapshot: snapshot())
        engine.receive(id: "right", profile: right, snapshot: snapshot([.a]))
        engine.configure(profile: KeyProfile(), deadzone: 0.2, speed: 15, centers: [:])
        #expect(events.suffix(2) == ["enter:true", "enter:false"])
    }
    @Test func pausedModeKeepsRecoveryButtonAfterProfileChange() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule)
        var toggles = 0; engine.output = { if $0.action == .toggleMode && $1 { toggles += 1 } }
        engine.setEnabled(false)
        var profile = KeyProfile(); profile.mapping[.home] = .init(action: .copy)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice("right", baseline: snapshot())
        engine.receive(id: "right", profile: JoyConProfile.all[1], snapshot: snapshot([.home]))
        #expect(toggles == 1)
    }
    @Test func stickStopsOnStaleInputAndDisconnect() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        var moves = 0, events: [String] = []
        engine.pointer = { _, _ in moves += 1 }; engine.output = { events.append("\($0.action.rawValue):\($1)") }
        engine.selectDevice("left", baseline: snapshot())
        engine.cycleStickMode(for: .left)
        engine.receive(id: "left", profile: JoyConProfile.all[0], snapshot: snapshot([.l], stick: .init(x: 4095, y: 2048)))
        engine.tick(); #expect(moves == 1)
        clock.advance(0.6); engine.tick(); #expect(moves == 1)
        clock.advance(1.5); engine.tick(); #expect(events == ["browserBack:true", "browserBack:false"])
    }
    @Test func directionalStickAndButtonsShareHoldCounts() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        var events: [String] = []; engine.output = { events.append("\($0.action.rawValue):\($1)") }
        engine.selectDevice("left", baseline: snapshot())
        engine.receive(id: "left", profile: JoyConProfile.all[0], snapshot: snapshot([.right], stick: .init(x: 4095, y: 2048)))
        engine.tick(); #expect(events == ["arrowRight:true"])
        engine.receive(id: "left", profile: JoyConProfile.all[0], snapshot: snapshot([], stick: .init(x: 4095, y: 2048)))
        #expect(events.count == 1)
        engine.disconnect("left"); #expect(events == ["arrowRight:true", "arrowRight:false"])
    }
    @Test func macroCancellationAndNoRecursion() {
        let clock = TestClock(), executor = MacroExecutor(schedule: clock.schedule)
        var events: [RemoteAction] = []; executor.output = { if $1 { events.append($0.action) } }
        let macro = ActionMacro(steps: [.init(mapping: .init(action: .copy), delay: 1), .init(mapping: .init(action: .paste))])
        executor.run(macro); clock.advance(0); #expect(events == [.copy])
        executor.cancel(); clock.advance(10); #expect(events == [.copy])
        executor.run(.init(steps: [.init(mapping: .init(action: .macro)), .init(mapping: .init(action: .toggleMode))]))
        clock.advance(10); #expect(events == [.copy])
    }
}

extension RuntimeTests {
    @Test func startupDoesNotRetryAnEarlierUseOfTheSameCommand() {
        let clock = TestClock(), queue = CommandQueue(schedule: clock.schedule)
        let initial = ControllerCommand.ble(0x0c, 4, [0x94, 0, 0, 0])
        let final = ControllerCommand.ble(0x0c, 4, [3, 0, 0, 0])
        var writes: [[UInt8]] = [], failed = false
        queue.write = { writes.append($0); return true }
        queue.failed = { _ in failed = true }
        queue.start([initial, final])
        clock.advance(1.5)
        queue.reply(command: 0x0c, subcommand: 4, success: true)
        #expect(writes == [initial.data])
        #expect(failed)
        #expect(!queue.running)
    }
}
