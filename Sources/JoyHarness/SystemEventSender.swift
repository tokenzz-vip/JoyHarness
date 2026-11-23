import AppKit
import Carbon.HIToolbox
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

    static let fnNavigation: [CGKeyCode: CGKeyCode] = [
        delete: CGKeyCode(kVK_ForwardDelete),
        upArrow: CGKeyCode(kVK_PageUp),
        downArrow: CGKeyCode(kVK_PageDown),
        leftArrow: CGKeyCode(kVK_Home),
        rightArrow: CGKeyCode(kVK_End)
    ]
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
    static let keyboardEventMarker: Int64 = 0x4A6F_7948_6172_6E73
    // Posting at cghidEventTap does not change a nil source's state table.
    // Keep Fn in the HID table, as on the physical Fn/Globe keyboard path.
    private let functionKeySource = CGEventSource(stateID: .hidSystemState)
    private var heldModifiers: [VoiceShortcutKey: Int] = [:]
    private var heldKeys: [CGKeyCode: Int] = [:]
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
        case .enter: holdKey(VirtualKey.returnKey, pressed: pressed)
        case .backspace: holdKey(VirtualKey.delete, pressed: pressed)
        case .escape: holdKey(VirtualKey.escape, pressed: pressed)
        case .arrowUp: holdKey(VirtualKey.upArrow, pressed: pressed)
        case .arrowDown: holdKey(VirtualKey.downArrow, pressed: pressed)
        case .arrowLeft: holdKey(VirtualKey.leftArrow, pressed: pressed)
        case .arrowRight: holdKey(VirtualKey.rightArrow, pressed: pressed)
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
        case .copy: holdKey(VirtualKey.c, flags: .maskCommand, pressed: pressed)
        case .paste: holdKey(VirtualKey.v, flags: .maskCommand, pressed: pressed)
        case .browserBack: holdKey(VirtualKey.leftBracket, flags: .maskCommand, pressed: pressed)
        case .browserForward: holdKey(VirtualKey.rightBracket, flags: .maskCommand, pressed: pressed)
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
                event.setIntegerValueField(.eventSourceUserData, value: Self.keyboardEventMarker)
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
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: pressed) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.keyboardEventMarker)
        postEvent(event)
    }

    private func holdKey(_ code: CGKeyCode, flags: CGEventFlags = [], pressed: Bool) {
        let count = heldKeys[code, default: 0]
        if pressed {
            heldKeys[code] = count + 1
            key(code, flags: flags, pressed: true)
        } else if count > 1 {
            heldKeys[code] = count - 1
        } else {
            heldKeys.removeValue(forKey: code)
            key(code, pressed: false)
        }
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
        key(modifier.keyCode, flags: heldModifierFlags, pressed: pressed,
            source: modifier == .function ? functionKeySource : nil)
    }

    private var heldModifierFlags: CGEventFlags {
        heldModifiers.keys.reduce(CGEventFlags()) { $0.union($1.flags) }
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
        var flags = CGEventFlags(rawValue: shortcut.modifiers)
        let modifier = ShortcutRecordingSession.modifierKeys.first { $0.code == shortcut.keyCode }
        if let modifier {
            guard !heldModifiers.keys.contains(where: { $0.keyCode == modifier.code }) else { return }
            flags.formUnion(modifier.flag.union(modifier.side).union(heldModifierFlags))
        }
        let usesFn = flags.contains(.maskSecondaryFn)
        if usesFn && functionKeySource == nil { return }
        let code = usesFn ? VirtualKey.fnNavigation[shortcut.keyCode] ?? shortcut.keyCode : shortcut.keyCode
        let source = usesFn ? functionKeySource : nil
        key(code, flags: flags, pressed: true, source: source)
        if heldKeys[code] == nil {
            key(code, flags: heldModifierFlags, pressed: false, source: source)
        }
    }
}
