import Foundation

struct StickPosition: Equatable {
    var x: Int
    var y: Int
    static let neutral = Self(x: 2048, y: 2048)
    func directions(side: JoyConSide, center: StickCenter? = nil, deadzone: Double,
                    previous: Set<ControllerInput> = []) -> Set<ControllerInput> {
        let vector = normalized(center: center, deadzone: deadzone)
        let inputs = ControllerInput.stickDirections(for: side)
        let values = [vector.y, -vector.y, -vector.x, vector.x]
        // Different enter/exit thresholds stop noise around the boundary from
        // repeatedly tapping actions. Returning to the deadzone always releases.
        return Set(zip(inputs, values).compactMap { input, value in
            value > (previous.contains(input) ? 0.2 : 0.3) ? input : nil
        })
    }
    func normalized(center: StickCenter? = nil, deadzone: Double) -> (x: Double, y: Double) {
        let cx = center?.x ?? 2048, cy = center?.y ?? 2048
        func axis(_ value: Int, _ center: Int) -> Double {
            let delta = Double(value - center)
            let span = Double(delta >= 0 ? max(4095 - center, 1) : max(center, 1))
            return max(-1, min(1, delta / span))
        }
        let nx = axis(x, cx), ny = axis(y, cy), length = hypot(nx, ny)
        guard length > deadzone else { return (0, 0) }
        let scale = min(1, (length - deadzone) / (1 - deadzone)) / length
        return (nx * scale, ny * scale)
    }
}
struct JoyConSnapshot: Equatable {
    var buttons: Set<ControllerInput>
    var stick: StickPosition
    var battery: Int?
    var charging: Bool
}

enum JoyConDecoder {
    private static func packedStick(_ b: [UInt8], offset: Int) -> StickPosition {
        .init(x: Int(b[offset]) | Int(b[offset + 1] & 0xf) << 8,
              y: Int(b[offset + 1] >> 4) | Int(b[offset + 2]) << 4)
    }
    private static func buttons(_ byte: UInt8, _ map: [ControllerInput?]) -> Set<ControllerInput> {
        Set(map.enumerated().compactMap { index, input in byte & (1 << index) != 0 ? input : nil })
    }
    /// HID buffers are normalized to include the report ID by the transport.
    static func firstGeneration(_ b: [UInt8], side: JoyConSide) -> JoyConSnapshot? {
        guard let id = b.first, [0x21, 0x30, 0x31].contains(id), b.count >= (id == 0x21 ? 15 : 49) else { return nil }
        var pressed: Set<ControllerInput>
        if side == .left {
            pressed = buttons(b[5], [.down, .up, .right, .left, .leftSR, .leftSL, .l, .zl])
            pressed.formUnion(buttons(b[4], [.minus, nil, nil, .leftStick, nil, .capture, nil, nil]))
        } else {
            pressed = buttons(b[3], [.y, .x, .b, .a, .rightSR, .rightSL, .r, .zr])
            pressed.formUnion(buttons(b[4], [nil, .plus, .rightStick, nil, .home, nil, nil, nil]))
        }
        let level = Int((b[2] >> 4) & 0xe)
        return .init(buttons: pressed, stick: packedStick(b, offset: side == .left ? 6 : 9),
                     battery: level <= 8 ? level * 100 / 8 : nil, charging: b[2] & 0x10 != 0)
    }
    /// The device-info response contains the controller address at payload offset 4.
    static func firstGenerationAddress(_ report: [UInt8]) -> String? {
        guard report.count >= 25, report[0] == 0x21, report[13] & 0x80 != 0, report[14] == 0x02 else { return nil }
        let address = report[19..<25]
        guard !address.allSatisfy({ $0 == 0 }), !address.allSatisfy({ $0 == 255 }) else { return nil }
        return address.map { String(format: "%02X", $0) }.joined()
    }

    static func firstGenerationBatteryEstimate(_ report: [UInt8]) -> Int? {
        guard report.count >= 17, report[0] == 0x21,
              report[13] == 0xd0, report[14] == 0x50, report[2] & 0x10 == 0 else { return nil }
        let voltage = Int(report[15]) | (Int(report[16]) << 8)
        guard (1320...1680).contains(voltage) else { return nil }

        // Joy-Con Toolkit's piecewise voltage curve, in the controller's raw units.
        switch voltage {
        case ..<1376: return 1
        case ..<1440: return Int(Double(voltage - 1376) / 7 + 1)
        case ..<1504: return Int(Double(voltage - 1440) / 2.625 + 11)
        case ..<1560: return Int(Double(voltage - 1504) / 1.8965 + 36)
        case ..<1624: return Int(Double(voltage - 1560) / 1.8529 + 66)
        default: return 100
        }
    }

    /// Native GATT notification, exactly 63 bytes; no HID report-ID prefix.
    static func secondGeneration(_ b: [UInt8], side: JoyConSide) -> JoyConSnapshot? {
        guard b.count == 63 else { return nil }
        var pressed: Set<ControllerInput>
        if side == .left {
            pressed = buttons(b[2], [.down, .right, .left, .up, .l, .zl, .minus, .leftStick])
            pressed.formUnion(buttons(b[3], [.capture, nil, .gl, nil, nil, nil, .leftSR, .leftSL]))
        } else {
            pressed = buttons(b[2], [.b, .a, .y, .x, .r, .zr, .plus, .rightStick])
            pressed.formUnion(buttons(b[3], [.home, nil, .gr, nil, .c, nil, .rightSR, .rightSL]))
        }
        let level = Int((b[1] >> 2) & 0xf)
        return .init(buttons: pressed, stick: packedStick(b, offset: 5),
                     battery: level <= 9 ? min(100, level * 100 / 8) : nil, charging: b[1] & 2 != 0)
    }
}

struct ControllerCommand: Equatable {
    let data: [UInt8]
    let command: UInt8?
    let subcommand: UInt8?
    var waitForInput = false
    var optional = false
    static func ble(_ command: UInt8, _ sub: UInt8, _ payload: [UInt8] = [], wait: Bool = false) -> Self {
        .init(data: [command, 0x91, 1, sub, 0, UInt8(payload.count), 0, 0] + payload,
              command: command, subcommand: sub, waitForInput: wait)
    }
    static let secondGenerationStartup: [Self] = [
        .ble(3, 0x0d, [1, 0, 255, 255, 255, 255, 255, 255]),
        .ble(7, 1), .ble(0x16, 1), .ble(0x15, 3, [0]),
        .ble(0x0c, 2, [0x94, 0, 0, 0]), .ble(0x11, 3),
        .ble(0x0a, 8, [1, 255, 255, 255, 255, 255, 255, 255, 255, 0x35, 0, 0x46, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        .ble(0x0c, 4, [0x94, 0, 0, 0]),
        .ble(3, 0x0a, [9, 0, 0, 0], wait: true),
        .init(data: [1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0x30], command: nil, subcommand: nil),
        // Only buttons and sticks are requested; motion/optical output is not consumed.
        .ble(0x0c, 2, [3, 0, 0, 0]), .ble(0x0c, 4, [3, 0, 0, 0]),
        .ble(8, 2, [1, 0, 0, 0]), .ble(9, 7, [1, 0, 0, 0, 0, 0, 0, 0]),
    ]
    static func hid(_ subcommand: UInt8, payload: [UInt8], counter: UInt8, optional: Bool = false) -> Self {
        var data: [UInt8] = [1, counter & 0xf, 0, 1, 0x40, 0x40, 0, 1, 0x40, 0x40, subcommand] + payload
        data += Array(repeating: 0, count: max(0, 49 - data.count))
        return .init(data: data, command: subcommand, subcommand: nil, optional: optional)
    }
}

/// Acknowledged commands, bounded retries, and a live-input barrier. The injected
/// scheduler makes timeouts testable without sleeping or touching hardware.
@MainActor
final class CommandQueue {
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> DispatchWorkItem
    nonisolated static let mainQueue: Scheduler = { delay, block in
        let work = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }
    private let schedule: Scheduler
    private var commands: [ControllerCommand] = []
    private var index = 0
    private var attempts = 0
    private var receivedInput = false
    private var awaitingInput = false
    private var awaitingReply = false
    private var work: DispatchWorkItem?
    var write: (([UInt8]) -> Bool)?
    var completed: (() -> Void)?
    var failed: ((String) -> Void)?
    private(set) var running = false

    init(schedule: @escaping Scheduler = CommandQueue.mainQueue) { self.schedule = schedule }
    func start(_ commands: [ControllerCommand]) {
        cancel(); self.commands = commands; index = 0; attempts = 0; receivedInput = false
        running = true; send()
    }
    func cancel() { work?.cancel(); work = nil; running = false; awaitingInput = false; awaitingReply = false }
    func reply(command: UInt8, subcommand: UInt8? = nil, success: Bool) {
        guard running, awaitingReply, !awaitingInput, index < commands.count,
              commands[index].command == command, commands[index].subcommand == subcommand else { return }
        awaitingReply = false
        work?.cancel()
        guard success else { reject("手柄拒绝初始化命令，请重新连接。"); return }
        if commands[index].waitForInput && !receivedInput {
            awaitingInput = true
            work = schedule(4) { [weak self] in self?.fail("等待手柄输入超时，请按 SYNC 后重新扫描。") }
        } else { advance() }
    }
    func inputReceived() {
        receivedInput = true
        if awaitingInput { awaitingInput = false; work?.cancel(); advance() }
    }
    private func send() {
        guard running else { return }
        guard index < commands.count else { running = false; completed?(); return }
        attempts += 1
        awaitingReply = commands[index].command != nil
        if commands[index].waitForInput { receivedInput = false }
        let current = commands[index]
        // Replies have no transaction ID. Retrying an earlier use of the same
        // command could leave a duplicate acknowledgement for its later use.
        let reused = current.command != nil && commands.dropFirst(index + 1).contains {
            $0.command == current.command && $0.subcommand == current.subcommand
        }
        let attemptLimit = current.optional || reused ? 1 : 3
        guard write?(current.data) == true else { reject("无法写入手柄初始化命令。"); return }
        if commands[index].command == nil { advance(); return }
        work = schedule(1) { [weak self] in
            guard let self, self.running else { return }
            if self.attempts >= attemptLimit { self.reject("手柄初始化应答超时，请重新连接。") }
            else { self.send() }
        }
    }
    private func reject(_ message: String) {
        if commands[index].optional { advance() } else { fail(message) }
    }
    private func advance() {
        awaitingReply = false
        index += 1; attempts = 0
        work = schedule(0.01) { [weak self] in self?.send() }
    }
    private func fail(_ message: String) { guard running else { return }; cancel(); failed?(message) }
}
