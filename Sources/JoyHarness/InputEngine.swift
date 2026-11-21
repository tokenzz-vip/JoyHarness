import Foundation

struct InputSource: Hashable {
    let deviceID: String
    let input: ControllerInput
}

@MainActor
final class GestureController {
    static let doubleTapWindow: TimeInterval = 0.3

    private final class Session {
        let single: ButtonMapping
        let double: ButtonMapping
        let long: ButtonMapping
        var held = true
        var second = false
        var longFired = false
        var work: DispatchWorkItem?
        var immediate: Bool { double.action == .disabled && long.action == .disabled }
        init(_ input: ControllerInput, _ mapping: RemoteMapping) {
            single = mapping[input]; double = mapping[input, .double]; long = mapping[input, .long]
        }
    }
    private var sessions: [InputSource: Session] = [:]
    private let schedule: CommandQueue.Scheduler
    var output: ((ButtonMapping, Bool) -> Void)?
    init(schedule: @escaping CommandQueue.Scheduler = CommandQueue.mainQueue) { self.schedule = schedule }
    func handle(_ source: InputSource, pressed: Bool, mapping: RemoteMapping) {
        if pressed {
            if let old = sessions[source] {
                guard !old.held else { return }
                old.work?.cancel(); old.held = true; old.second = true; scheduleLong(old, source)
            } else {
                let session = Session(source.input, mapping); sessions[source] = session
                if session.immediate { output?(session.single, true) } else { scheduleLong(session, source) }
            }
        } else {
            guard let session = sessions[source], session.held else { return }
            session.held = false; session.work?.cancel()
            if session.immediate { sessions[source] = nil; output?(session.single, false) }
            else if session.longFired { sessions[source] = nil }
            else if session.second { sessions[source] = nil; tap(session.double) }
            else if session.double.action != .disabled {
                session.work = schedule(Self.doubleTapWindow) { [weak self, weak session] in
                    guard let self, let session, self.sessions[source] === session, !session.held else { return }
                    self.sessions[source] = nil; self.tap(session.single)
                }
            } else { sessions[source] = nil; tap(session.single) }
        }
    }
    private func scheduleLong(_ session: Session, _ source: InputSource) {
        guard session.long.action != .disabled else { return }
        session.work = schedule(0.55) { [weak self, weak session] in
            guard let self, let session, self.sessions[source] === session, session.held else { return }
            session.longFired = true; self.tap(session.long)
        }
    }
    func cancel(deviceID: String? = nil) {
        let old = sessions.filter { deviceID == nil || $0.key.deviceID == deviceID }
        for source in old.keys { cancel(source: source) }
    }
    func cancel(source: InputSource) {
        guard let session = sessions.removeValue(forKey: source) else { return }
        session.work?.cancel()
        if session.immediate && session.held { output?(session.single, false) }
    }
    private func tap(_ mapping: ButtonMapping) { output?(mapping, true); output?(mapping, false) }
}

@MainActor
final class InputEngine {
    static let reportTimeout: TimeInterval = 2
    private struct DeviceInput {
        var profile: JoyConProfile
        var snapshot: JoyConSnapshot
        var lastInput: TimeInterval
    }
    private let gestures: GestureController
    private let now: () -> TimeInterval
    private var devices: [String: DeviceInput] = [:]
    private(set) var selectedDeviceID: String?
    private var suppressedButtons: Set<ControllerInput> = []
    private var inputCaptured = false
    private var awaitingFirstReport = true
    private var awaitingNeutralStick = true
    private var pointerRemainder = CGPoint.zero
    private var heldOutputs: [ButtonMapping: Int] = [:]
    private var activeVoiceTap: ButtonMapping?
    private(set) var mouseButtonBindings = MouseButtonBindings()
    private var pausedMapping = RemoteMapping()
    private var activeStickMode = StickMode.mapped
    private var stickModeRevision = 0
    private(set) var enabled = true
    var profile = KeyProfile()
    var deadzone = 0.18
    var speed = 14.0
    var centers: [String: StickCenter] = [:]
    var output: ((ButtonMapping, Bool) -> Void)?
    var pointer: ((Double, Double) -> Void)?
    var buttonPressed: ((ControllerInput) -> Void)?
    var onStale: ((String) -> Void)?
    var onStickModeChange: ((JoyConSide, StickMode) -> Void)?

    init(schedule: @escaping CommandQueue.Scheduler = CommandQueue.mainQueue,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now; gestures = GestureController(schedule: schedule)
        gestures.output = { [weak self] in self?.emit($0, pressed: $1) }
    }
    func selectDevice(_ id: String?, baseline: JoyConSnapshot? = nil) {
        cancel()
        devices.removeAll()
        activeStickMode = .mapped
        selectedDeviceID = id
        suppressedButtons = baseline?.buttons ?? []
        awaitingFirstReport = baseline == nil
        let vector = baseline?.stick.normalized(center: id.flatMap { centers[$0] }, deadzone: deadzone)
        awaitingNeutralStick = vector == nil || vector!.x != 0 || vector!.y != 0
    }
    func configure(profile: KeyProfile, deadzone: Double, speed: Double, centers: [String: StickCenter], mouseButtons: MouseButtonBindings = .init()) {
        let changed = self.profile != profile || self.deadzone != deadzone || self.speed != speed
            || self.centers != centers || mouseButtonBindings != mouseButtons
        cancel()
        if changed && activeStickMode == .pointer {
            activeStickMode = .mapped
            stickModeRevision += 1
            awaitingNeutralStick = true
        }
        self.profile = profile; self.deadzone = deadzone; self.speed = speed; self.centers = centers
        self.mouseButtonBindings = mouseButtons
    }
    func stickMode(for _: JoyConSide) -> StickMode { activeStickMode }
    func cycleStickMode(for side: JoyConSide) {
        guard enabled else { return }
        let next = activeStickMode.next
        activeStickMode = next
        stickModeRevision += 1
        // Finish old direction gestures before accepting the new mode. A tilted
        // stick must return to center so this press cannot also move the pointer.
        for (id, device) in Array(devices) where id == selectedDeviceID {
            for input in ControllerInput.stickDirections(for: device.profile.side) {
                gestures.cancel(source: .init(deviceID: id, input: input))
                devices[id]?.snapshot.buttons.remove(input)
            }
            for input in [mouseButtonBindings.left, mouseButtonBindings.right].compactMap({ $0 }) {
                gestures.cancel(source: .init(deviceID: id, input: input))
            }
            devices[id]?.snapshot.stick = .init(x: centers[id]?.x ?? 2048, y: centers[id]?.y ?? 2048)
            awaitingNeutralStick = true
            pointerRemainder = .zero
        }
        onStickModeChange?(side, next)
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        cancel()
        enabled = value
        refreshPausedMapping()
    }
    func refreshPausedMapping() {
        guard !enabled else { return }
        pausedMapping = .init(buttons: profile.mapping.buttons.filter { $0.value.action == .toggleMode })
    }
    func setInputCaptured(_ captured: Bool) {
        guard inputCaptured != captured else { return }
        inputCaptured = captured
        if captured {
            cancel()
        } else if let id = selectedDeviceID, let snapshot = devices[id]?.snapshot {
            suppressedButtons = snapshot.buttons.filter { !$0.isStickDirection }
            let stick = snapshot.stick.normalized(center: centers[id], deadzone: deadzone)
            awaitingNeutralStick = stick.x != 0 || stick.y != 0
        }
    }

    func receive(id: String, profile: JoyConProfile, snapshot: JoyConSnapshot) {
        guard id == selectedDeviceID else { return }
        if inputCaptured {
            // Keep connection timeouts and the resume baseline current while the picker owns input.
            devices[id] = .init(profile: profile, snapshot: snapshot, lastInput: now())
            return
        }
        var snapshot = snapshot
        if awaitingFirstReport {
            suppressedButtons = snapshot.buttons
            awaitingFirstReport = false
        }
        suppressedButtons.formIntersection(snapshot.buttons)
        snapshot.buttons.subtract(suppressedButtons)
        if awaitingNeutralStick {
            let vector = snapshot.stick.normalized(center: centers[id], deadzone: deadzone)
            if vector.x == 0 && vector.y == 0 { awaitingNeutralStick = false }
            else { snapshot.stick = .init(x: centers[id]?.x ?? 2048, y: centers[id]?.y ?? 2048) }
        }
        let old = devices[id]?.snapshot.buttons ?? []
        let mode = activeStickMode
        let directionRecovery = !enabled && ControllerInput.stickDirections(for: profile.side).contains { input in
            Gesture.allCases.contains { pausedMapping[input, $0].action == .toggleMode }
        }
        if mode == .mapped || directionRecovery {
            snapshot.buttons.formUnion(snapshot.stick.directions(side: profile.side, center: centers[id], deadzone: deadzone,
                                                               previous: old))
        }
        devices[id] = .init(profile: profile, snapshot: snapshot, lastInput: now())
        let revision = stickModeRevision
        for input in old.subtracting(snapshot.buttons) {
            guard !inputCaptured else { return }
            gestures.handle(.init(deviceID: id, input: input), pressed: false, mapping: self.profile.mapping)
        }
        for input in snapshot.buttons.subtracting(old).sorted(by: {
            if $0.isStickDirection != $1.isStickDirection { return !$0.isStickDirection }
            return $0.rawValue < $1.rawValue
        }) {
            guard !inputCaptured else { return }
            if input.isStickDirection && revision != stickModeRevision { continue }
            buttonPressed?(input)
            let mapping = mappingFor(input, mapping: enabled ? self.profile.mapping : pausedMapping, mode: activeStickMode)
            let action = mapping[input]
            if action.voiceShortcut?.mode == .tap {
                activeVoiceTap = activeVoiceTap == nil ? action : nil
                pulseVoiceShortcut(action)
                continue
            }
            if !input.isStickDirection { endVoiceTap() }
            gestures.handle(.init(deviceID: id, input: input), pressed: true, mapping: mapping)
        }
    }
    func disconnect(_ id: String) {
        gestures.cancel(deviceID: id); devices[id] = nil
        if id == selectedDeviceID {
            endVoiceTap()
            pointerRemainder = .zero
            awaitingFirstReport = true; awaitingNeutralStick = true; suppressedButtons = []
        }
    }
    func cancel() {
        pointerRemainder = .zero
        endVoiceTap()
        gestures.cancel()
    }

    private func pulseVoiceShortcut(_ mapping: ButtonMapping) {
        emit(mapping, pressed: true)
        emit(mapping, pressed: false)
    }

    private func endVoiceTap() {
        guard let mapping = activeVoiceTap else { return }
        activeVoiceTap = nil
        pulseVoiceShortcut(mapping)
    }
    func tick() {
        for (id, device) in Array(devices) {
            guard enabled, !inputCaptured, now() - device.lastInput < 0.5 else {
                pointerRemainder = .zero
                if now() - device.lastInput >= 0.5 {
                    for input in ControllerInput.stickDirections(for: device.profile.side) {
                        gestures.cancel(source: .init(deviceID: id, input: input))
                        devices[id]?.snapshot.buttons.remove(input)
                    }
                }
                continue
            }
            guard activeStickMode == .pointer else { continue }
            let vector = device.snapshot.stick.normalized(center: centers[id], deadzone: deadzone)
            movePointer(x: vector.x * speed, y: -vector.y * speed)
        }
        // Full input reports are periodic for both transports. Stop stale holds
        // even when Bluetooth has not yet delivered a disconnect notification.
        for (id, device) in Array(devices) where now() - device.lastInput >= Self.reportTimeout { disconnect(id); onStale?(id) }
    }

    private func movePointer(x: Double, y: Double) {
        guard x != 0 || y != 0 else {
            pointerRemainder = .zero
            return
        }
        let totalX = x + pointerRemainder.x
        let totalY = y + pointerRemainder.y
        let deltaX = totalX.rounded(.towardZero)
        let deltaY = totalY.rounded(.towardZero)
        pointerRemainder = CGPoint(x: totalX - deltaX, y: totalY - deltaY)
        if deltaX != 0 || deltaY != 0 { pointer?(deltaX, deltaY) }
    }

    private func mappingFor(_ input: ControllerInput, mapping: RemoteMapping, mode: StickMode) -> RemoteMapping {
        guard enabled, mode == .pointer else { return mapping }
        var result = mapping
        let action: RemoteAction?
        if mouseButtonBindings.left == input { action = .mouseLeft }
        else if mouseButtonBindings.right == input { action = .mouseRight }
        else { action = nil }
        if let action {
            result[input] = .init(action: action)
            result[input, .double] = .init()
            result[input, .long] = .init()
        }
        return result
    }

    private func emit(_ mapping: ButtonMapping, pressed: Bool) {
        guard mapping.action != .disabled else { return }
        if pressed {
            let count = heldOutputs[mapping] ?? 0; heldOutputs[mapping] = count + 1
            if count == 0 { output?(mapping, true) }
        } else {
            guard let count = heldOutputs[mapping] else { return }
            if count <= 1 { heldOutputs[mapping] = nil; output?(mapping, false) }
            else { heldOutputs[mapping] = count - 1 }
        }
    }
}

@MainActor
final class MacroExecutor {
    private var work: [DispatchWorkItem] = []
    private let schedule: CommandQueue.Scheduler
    var output: ((ButtonMapping, Bool) -> Void)?
    init(schedule: @escaping CommandQueue.Scheduler = CommandQueue.mainQueue) { self.schedule = schedule }
    func run(_ macro: ActionMacro, library: [ActionMacro] = []) {
        cancel()
        guard let plan = try? MacroExecutionPlan(macro, macros: library) else { return }
        for event in plan.events {
            let mapping = event.mapping
            work.append(schedule(event.offset) { [weak self] in self?.output?(mapping, true); self?.output?(mapping, false) })
        }
    }
    func cancel() { work.forEach { $0.cancel() }; work.removeAll() }
}
