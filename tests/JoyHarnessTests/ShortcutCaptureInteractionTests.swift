import AppKit
import CoreGraphics
import ObjectiveC
import XCTest
@testable import JoyHarness

@MainActor
final class ShortcutCaptureInteractionTests: XCTestCase {
    private final class RecordingWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    func testLocalDispatchCapturesEscapeAndReturnBeforeWindowRouting() throws {
        _ = NSApplication.shared
        // The test dispatches events inside AppKit without activating the test runner.
        let getter = try XCTUnwrap(class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)))
        let active: @convention(block) (AnyObject) -> Bool = { _ in true }
        let implementation = imp_implementationWithBlock(active)
        let original = method_setImplementation(getter, implementation)
        defer {
            method_setImplementation(getter, original)
            imp_removeBlock(implementation)
        }

        for code in [VirtualKey.escape, VirtualKey.returnKey] {
            let window = RecordingWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                         styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let session = ShortcutRecordingSession()
            let field = ShortcutCapture.CaptureField(session: session)
            window.contentView = field
            defer { window.close() }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertTrue(session.isRecording)
            XCTAssertTrue(window.firstResponder === field)
            var result: RecordedShortcut?
            session.onCapture = { result = $0 }
            for pressed in [true, false] {
                let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: pressed))
                event.flags = []
                NSApp.sendEvent(try XCTUnwrap(NSEvent(cgEvent: event)))
            }
            XCTAssertEqual(result?.keyCode, code)
            XCTAssertFalse(session.isRecording)
        }
    }
}
