import CoreGraphics

enum VoiceTriggerMode: String, Codable, Hashable {
    case hold, tap

    var title: String { self == .hold ? "长按模式" : "点按模式" }
}

enum VoiceShortcutKey: String, CaseIterable, Codable, Hashable {
    case function, leftCommand, rightCommand, leftOption, rightOption, leftControl, rightControl

    var label: String {
        switch self {
        case .function: "Fn／地球键"
        case .leftCommand: "左侧 Command"
        case .rightCommand: "右侧 Command"
        case .leftOption: "左侧 Option"
        case .rightOption: "右侧 Option"
        case .leftControl: "左侧 Control"
        case .rightControl: "右侧 Control"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .function: VirtualKey.function
        case .leftCommand: VirtualKey.command
        case .rightCommand: VirtualKey.rightCommand
        case .leftOption: VirtualKey.option
        case .rightOption: VirtualKey.rightOption
        case .leftControl: 0x3B
        case .rightControl: 0x3E
        }
    }

    // Include the device-dependent flag so listeners can tell left from right.
    var flags: CGEventFlags {
        switch self {
        case .function: .maskSecondaryFn
        case .leftCommand: [.maskCommand, CGEventFlags(rawValue: 0x08)]
        case .rightCommand: [.maskCommand, CGEventFlags(rawValue: 0x10)]
        case .leftOption: [.maskAlternate, CGEventFlags(rawValue: 0x20)]
        case .rightOption: [.maskAlternate, CGEventFlags(rawValue: 0x40)]
        case .leftControl: [.maskControl, CGEventFlags(rawValue: 0x01)]
        case .rightControl: [.maskControl, CGEventFlags(rawValue: 0x2000)]
        }
    }
}

struct VoiceShortcut: Codable, Hashable {
    let mode: VoiceTriggerMode
    let keys: Set<VoiceShortcutKey>

    var orderedKeys: [VoiceShortcutKey] { VoiceShortcutKey.allCases.filter(keys.contains) }
    var label: String { orderedKeys.map(\.label).joined(separator: " + ") }
}
