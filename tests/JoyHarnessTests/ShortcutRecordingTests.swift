import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import JoyHarness

@MainActor
struct ShortcutRecordingTests {
    private func send(_ type: CGEventType, _ code: Int, to session: ShortcutRecordingSession,
                      flags: CGEventFlags = [], repeating: Bool = false) throws {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: UInt16(code), keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
        #expect(session.handle(type, event: event))
    }

    @Test func overlappingMainKeysCanBeRetried() throws {
        let session = ShortcutRecordingSession()
        var result: RecordedShortcut?
        session.onCapture = { result = $0 }
        session.start()
        try send(.keyDown, kVK_ANSI_A, to: session)
        try send(.keyDown, kVK_ANSI_S, to: session)
        try send(.keyUp, kVK_ANSI_S, to: session)
        try send(.keyUp, kVK_ANSI_A, to: session)
        #expect(result == nil)
        guard session.isRecording else { return }
        try send(.keyDown, kVK_ANSI_D, to: session)
        try send(.keyUp, kVK_ANSI_D, to: session)
        #expect(result?.keyCode == UInt16(kVK_ANSI_D))
    }

    @Test func repeatFromKeyAlreadyHeldDoesNotPoisonNextChord() throws {
        let session = ShortcutRecordingSession()
        var result: RecordedShortcut?
        session.onCapture = { result = $0 }
        session.start()
        try send(.keyDown, kVK_ANSI_A, to: session, repeating: true)
        try send(.keyDown, kVK_ANSI_S, to: session)
        try send(.keyUp, kVK_ANSI_S, to: session)
        #expect(result?.keyCode == UInt16(kVK_ANSI_S))
    }

    @Test func capsLockAndSpecialKeyLabelsAreRecordable() throws {
        let session = ShortcutRecordingSession()
        var result: RecordedShortcut?
        session.onCapture = { result = $0 }
        session.start()
        try send(.flagsChanged, kVK_CapsLock, to: session, flags: .maskAlphaShift)
        #expect(result?.label == "Caps Lock")
        session.start()
        try send(.keyDown, kVK_Return, to: session)
        try send(.keyUp, kVK_Return, to: session)
        #expect(result?.label == "Return")
    }

    @Test func recordedModifierTapRespectsOtherHeldMappings() {
        var events: [CGEvent] = []
        let sender = SystemEventSender(postEvent: { events.append($0) })
        let held = ButtonMapping(action: .rightCommand)
        let tap = ButtonMapping(action: .recordedShortcut, shortcut:
            .init(keyCode: UInt16(kVK_RightCommand), modifiers: CGEventFlags.maskCommand.rawValue, label: "右侧 Command"))
        sender.send(held, pressed: true)
        sender.send(tap, pressed: true)
        #expect(events.count == 1)
        sender.send(held, pressed: false)
        #expect(events.map(\.flags) == [VoiceShortcutKey.rightCommand.flags, []])
        events.removeAll()
        sender.send(tap, pressed: true)
        #expect(events.map(\.flags) == [VoiceShortcutKey.rightCommand.flags, []])
    }

    @Test func recordedReturnTapDoesNotReleaseAnExistingHold() {
        var events: [CGEvent] = []
        let sender = SystemEventSender(postEvent: { events.append($0) })
        let held = ButtonMapping(action: .enter)
        let tap = ButtonMapping(action: .recordedShortcut, shortcut:
            .init(keyCode: VirtualKey.returnKey, modifiers: 0, label: "Return"))
        sender.send(held, pressed: true)
        sender.send(tap, pressed: true)
        #expect(events.map(\.type) == [.keyDown, .keyDown])
        sender.send(held, pressed: false)
        #expect(events.map(\.type) == [.keyDown, .keyDown, .keyUp])
    }

    @Test func functionFlagOnNavigationKeyDoesNotRequireFnRelease() throws {
        let session = ShortcutRecordingSession()
        var recordings: [RecordedShortcut] = []
        session.onCapture = { recordings.append($0) }
        session.start()
        try send(.keyDown, kVK_UpArrow, to: session, flags: .maskSecondaryFn)
        try send(.keyUp, kVK_UpArrow, to: session, flags: .maskSecondaryFn)
        #expect(recordings.last?.label == "↑")
        #expect(recordings.last?.modifiers == 0)

        session.start()
        try send(.flagsChanged, kVK_Function, to: session, flags: .maskSecondaryFn)
        try send(.keyDown, kVK_PageUp, to: session, flags: .maskSecondaryFn)
        try send(.keyUp, kVK_PageUp, to: session, flags: .maskSecondaryFn)
        #expect(recordings.count == 1)
        try send(.flagsChanged, kVK_Function, to: session)
        #expect(recordings.last?.label == "Fn + Page Up")
    }

    @Test func sameFamilyModifiersDoNotRecordAndRightShiftCanBeRetried() throws {
        let session = ShortcutRecordingSession()
        var result: RecordedShortcut?
        session.onCapture = { result = $0 }
        session.start()
        let left = CGEventFlags(rawValue: 0x02)
        let right = CGEventFlags(rawValue: 0x04)
        try send(.flagsChanged, kVK_Shift, to: session, flags: [.maskShift, left])
        try send(.flagsChanged, kVK_RightShift, to: session, flags: [.maskShift, left, right])
        try send(.flagsChanged, kVK_Shift, to: session, flags: [.maskShift, right])
        try send(.flagsChanged, kVK_RightShift, to: session)
        #expect(result == nil)
        try send(.flagsChanged, kVK_RightShift, to: session, flags: [.maskShift, right])
        try send(.flagsChanged, kVK_RightShift, to: session)
        #expect(result?.label == "右侧 Shift")
    }

    @Test func keyboardSelectionPreservesLegacyBindingAndUsesLayoutAfterAnEdit() throws {
        let code = UInt16(kVK_ANSI_Y)
        let original = RecordedShortcut(keyCode: code, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘Y")
        var selection = ShortcutKeyboardSelection(shortcut: original, keyLabels: [code: "Z"], commandKeyLabels: [code: "Y"])
        #expect(selection.shortcut == original)
        #expect(selection.keyLabels[code] == "Y")
        selection.toggle(.maskCommand)
        #expect(selection.shortcut?.label == "Z")
        selection.select(UInt16(kVK_RightShift))
        #expect(selection.shortcut?.label == "右侧 Shift")
        selection.toggle(.maskSecondaryFn)
        #expect(selection.shortcut == nil)
        selection.select(UInt16(kVK_UpArrow))
        let shortcut = try #require(selection.shortcut)
        #expect(shortcut.label == "Fn + ↑")

        var events: [CGEvent] = []
        let sender = SystemEventSender(postEvent: { events.append($0) })
        sender.send(.init(action: .recordedShortcut, shortcut: shortcut), pressed: true)
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        #expect(events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_PageUp) })
        #expect(events.first?.flags == .maskSecondaryFn)
        #expect(events.last?.flags == [])
    }

    @Test func synthesizedKeyboardEventsAreIgnoredDuringRecording() throws {
        let session = ShortcutRecordingSession()
        var result: RecordedShortcut?
        session.onCapture = { result = $0 }
        session.start()
        let sender = SystemEventSender(postEvent: { _ = session.handle($0.type, event: $0) })
        sender.send(.init(action: .enter), pressed: true)
        sender.send(.init(action: .enter), pressed: false)
        sender.typeText("a")
        #expect(result == nil)
        try send(.keyDown, kVK_Escape, to: session)
        try send(.keyUp, kVK_Escape, to: session)
        #expect(result?.label == "Esc")
    }
}
