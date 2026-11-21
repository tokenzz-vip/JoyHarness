import AppKit
import CoreGraphics
import Foundation

/// macOS virtual key codes (HIToolbox kVK_*) used by the built-in actions.
enum VirtualKey {
    static let returnKey: CGKeyCode = 0x24
    static let delete: CGKeyCode = 0x33
    static let escape: CGKeyCode = 0x35
    static let upArrow: CGKeyCode = 0x7E
    static let downArrow: CGKeyCode = 0x7D
    static let leftArrow: CGKeyCode = 0x7B
    static let rightArrow: CGKeyCode = 0x7C
    static let rightCommand: CGKeyCode = 0x36
    static let command: CGKeyCode = 0x37
    static let function: CGKeyCode = 0x3F
    static let option: CGKeyCode = 0x3A
    static let rightOption: CGKeyCode = 0x3D
    static let c: CGKeyCode = 0x08
    static let v: CGKeyCode = 0x09
    static let leftBracket: CGKeyCode = 0x21
    static let rightBracket: CGKeyCode = 0x1E
}

/// NX_KEYTYPE_* codes for system-defined media key events.
private enum MediaKey {
    static let soundUp = 0
    static let soundDown = 1
    static let mute = 7
    static let play = 16
}

/// Every synthesized event goes through `postEvent`, so tests can observe all
/// output without posting into the real session.
final class SystemEventSender {
    // Posting at cghidEventTap does not change a nil source's state table.
    // Keep Fn in the HID table, as on the physical Fn/Globe keyboard path.
    private let functionKeySource = CGEventSource(stateID: .hidSystemState)
    private var heldModifiers: [VoiceShortcutKey: Int] = [:]
    private var leftMouseHeld = false
    private var rightMouseHeld = false
    private let cursorLocation: () -> CGPoint
    private let postEvent: (CGEvent) -> Void
    private let movePointer: (CGPoint) -> Void
    private let openApplication: (URL) -> Void

    init(
        cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero },
        postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) },
        movePointer: @escaping (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) },
        openApplication: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.cursorLocation = cursorLocation
        self.postEvent = postEvent
        self.movePointer = movePointer
        self.openApplication = openApplication
    }

    func send(_ mapping: ButtonMapping, pressed: Bool) {
        switch mapping.action {
        case .enter: key(VirtualKey.returnKey, pressed: pressed)
        case .backspace: key(VirtualKey.delete, pressed: pressed)
        case .escape: key(VirtualKey.escape, pressed: pressed)
        case .arrowUp: key(VirtualKey.upArrow, pressed: pressed)
        case .arrowDown: key(VirtualKey.downArrow, pressed: pressed)
        case .arrowLeft: key(VirtualKey.leftArrow, pressed: pressed)
        case .arrowRight: key(VirtualKey.rightArrow, pressed: pressed)
        case .rightCommand: modifier(.rightCommand, pressed: pressed)
        case .leftCommand: modifier(.leftCommand, pressed: pressed)
        case .fn: modifier(.function, pressed: pressed)
        case .leftOption: modifier(.leftOption, pressed: pressed)
        case .rightOption: modifier(.rightOption, pressed: pressed)
        case .voiceShortcut:
            if let shortcut = mapping.voiceShortcut {
                let keys = shortcut.orderedKeys
                for key in pressed ? keys : Array(keys.reversed()) { modifier(key, pressed: pressed) }
            }
        case .copy: key(VirtualKey.c, flags: pressed ? .maskCommand : [], pressed: pressed)
        case .paste: key(VirtualKey.v, flags: pressed ? .maskCommand : [], pressed: pressed)
        case .browserBack: key(VirtualKey.leftBracket, flags: pressed ? .maskCommand : [], pressed: pressed)
        case .browserForward: key(VirtualKey.rightBracket, flags: pressed ? .maskCommand : [], pressed: pressed)
        case .mouseLeft: mouse(.left, pressed: pressed)
        case .mouseRight: mouse(.right, pressed: pressed)
        case .pointerUp: move(0, -12, pressed: pressed)
        case .pointerDown: move(0, 12, pressed: pressed)
        case .pointerLeft: move(-12, 0, pressed: pressed)
        case .pointerRight: move(12, 0, pressed: pressed)
        case .scrollUp: scroll(4, pressed: pressed)
        case .scrollDown: scroll(-4, pressed: pressed)
        case .recordedShortcut:
            if pressed, let shortcut = mapping.shortcut { shortcutEvent(shortcut) }
        case .openApplication:
            if pressed, let path = mapping.applicationPath { openApplication(URL(fileURLWithPath: path)) }
        case .volumeUp: mediaKey(MediaKey.soundUp, pressed: pressed)
        case .volumeDown: mediaKey(MediaKey.soundDown, pressed: pressed)
        case .mute: mediaKey(MediaKey.mute, pressed: pressed)
        case .playPause: mediaKey(MediaKey.play, pressed: pressed)
        case .phrase, .openPhrases, .macro, .toggleMode, .cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode,
             .focusChatGPT, .focusClaude, .focusCursor, .focusDeepSeek, .focusWorkBuddy, .focusOpenCode, .disabled: break
        }
    }

    func typeText(_ text: String) {
        var chunks: [[UInt16]] = [[]]
        // Never split a UTF-16 surrogate pair across two Unicode events.
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if chunks[chunks.count - 1].count + units.count > 20 { chunks.append([]) }
            chunks[chunks.count - 1].append(contentsOf: units)
        }
        for chunk in chunks where !chunk.isEmpty {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                postEvent(event)
            }
        }
    }

    private func mediaKey(_ code: Int, pressed: Bool) {
        let flags = pressed ? 0xA00 : 0xB00
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (code << 16) | flags, data2: -1)
        if let event = event?.cgEvent { postEvent(event) }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = [], pressed: Bool, source: CGEventSource? = nil) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: pressed)
        event?.flags = flags
        if let event { postEvent(event) }
    }

    private func modifier(_ modifier: VoiceShortcutKey, pressed: Bool) {
        if modifier == .function && functionKeySource == nil {
            Log.hid.error("Cannot create HID event source for Fn")
            return
        }
        let count = heldModifiers[modifier, default: 0]
        if pressed {
            heldModifiers[modifier] = count + 1
            guard count == 0 else { return }
        } else {
            guard count > 0 else { return }
            heldModifiers[modifier] = count > 1 ? count - 1 : nil
            guard count == 1 else { return }
        }
        let flags = heldModifiers.keys.reduce(CGEventFlags()) { $0.union($1.flags) }
        key(modifier.keyCode, flags: flags, pressed: pressed, source: modifier == .function ? functionKeySource : nil)
    }

    func pointer(from current: CGPoint, to point: CGPoint) {
        guard point != current else { return }
        let type: CGEventType = leftMouseHeld ? .leftMouseDragged : rightMouseHeld ? .rightMouseDragged : .mouseMoved
        let button: CGMouseButton = type == .rightMouseDragged ? .right : .left
        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) {
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - current.x).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - current.y).rounded()))
            postEvent(event)
        }
    }

    func scroll(x: Double, y: Double) {
        guard x != 0 || y != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32((y * 8).rounded()), wheel2: Int32((-x * 8).rounded()), wheel3: 0) else { return }
        postEvent(event)
    }

    private func mouse(_ button: CGMouseButton, pressed: Bool) {
        if button == .left { leftMouseHeld = pressed }
        if button == .right { rightMouseHeld = pressed }
        let type: CGEventType
        switch (button, pressed) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        default: return
        }
        if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cursorLocation(), mouseButton: button) {
            // Quartz defaults mouse-up to zero clicks. Report one click on both edges.
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            postEvent(event)
        }
    }

    private func move(_ x: CGFloat, _ y: CGFloat, pressed: Bool) {
        guard pressed else { return }
        let current = cursorLocation()
        movePointer(CGPoint(x: current.x + x, y: current.y + y))
    }

    private func scroll(_ value: Int32, pressed: Bool) {
        guard pressed, let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: value, wheel2: 0, wheel3: 0) else { return }
        postEvent(event)
    }

    private func shortcutEvent(_ shortcut: RecordedShortcut) {
        let flags = CGEventFlags(rawValue: shortcut.modifiers)
        key(CGKeyCode(shortcut.keyCode), flags: flags, pressed: true)
        key(CGKeyCode(shortcut.keyCode), flags: [], pressed: false)
    }
}
