import AppKit
import SwiftUI
import XCTest
@testable import JoyHarness

@MainActor
final class MacrosLayoutTests: XCTestCase {
    func testLongMacroListScrollsWithoutMovingTheEditor() throws {
        let suite = "JoyHarness.MacrosLayoutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        let macro = try XCTUnwrap(model.savedMacros.first)
        model.updateMacroSteps((0..<12).map { _ in MacroStep() }, for: macro.id)
        model.page = .macros
        let hostingView = NSHostingView(rootView: DashboardView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsStyle.minimumWindowSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()

        let panes = scrollViews(in: hostingView).filter {
            $0.convert($0.bounds, to: hostingView).minX > SettingsStyle.sidebarWidth
        }.sorted { $0.convert($0.bounds, to: hostingView).minX < $1.convert($1.bounds, to: hostingView).minX }
        XCTAssertEqual(panes.count, 2, "The macro list and editor must have independent scroll areas")
        guard panes.count == 2 else { return }
        let list = panes[0]
        let editor = panes[1]
        let document = try XCTUnwrap(list.documentView)
        XCTAssertGreaterThan(document.bounds.height, list.contentView.bounds.height)
        let editorFrame = editor.convert(editor.bounds, to: hostingView)
        XCTAssertLessThanOrEqual(editorFrame.maxY, hostingView.bounds.maxY)
        XCTAssertGreaterThanOrEqual(editorFrame.minY, hostingView.bounds.minY)

        list.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.height - list.contentView.bounds.height))
        list.reflectScrolledClipView(list.contentView)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(list.contentView.bounds.minY, 0)
        XCTAssertEqual(editor.convert(editor.bounds, to: hostingView), editorFrame,
                       "Scrolling to the last macro must keep the editor visible")

        let editorDocument = try XCTUnwrap(editor.documentView)
        XCTAssertGreaterThan(editorDocument.bounds.height, editor.contentView.bounds.height)
        let listPosition = list.contentView.bounds.origin
        editor.contentView.scroll(to: CGPoint(x: 0, y: editorDocument.bounds.height - editor.contentView.bounds.height))
        editor.reflectScrolledClipView(editor.contentView)
        hostingView.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(editor.contentView.bounds.minY, 0)
        XCTAssertEqual(list.contentView.bounds.origin, listPosition,
                       "Scrolling a long action must not move the macro list")
    }

    func testSwitchingToMacrosShowsBothScrollAreas() {
        let suite = "JoyHarness.MacrosSwitchTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        // The mapping page uses Canvas, which needs GPU support the Intel CI VM lacks.
        model.page = .profiles
        let hostingView = NSHostingView(rootView: DashboardView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: CGSize(width: 1120, height: 820)),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        for attempt in 1...3 {
            model.page = .profiles
            guard waitForContentPanes(1, in: hostingView) else {
                return XCTFail("Attempt \(attempt): The profiles page did not replace the macro panes")
            }
            let start = ProcessInfo.processInfo.systemUptime
            model.page = .macros
            guard waitForContentPanes(2, in: hostingView, startingAt: start) else {
                return XCTFail("Attempt \(attempt): The macro list and editor did not both appear")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("Macro page switch \(attempt): \(Int(elapsed * 1000)) ms (\(model.savedMacros.count) macros)")
        }
    }

    private func waitForContentPanes(_ expected: Int, in hostingView: NSView,
                                     startingAt start: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        // SwiftUI can reconcile an observed change on a later run-loop turn.
        let deadline = start + 2
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            let paneCount = scrollViews(in: hostingView).filter {
                $0.convert($0.bounds, to: hostingView).minX > SettingsStyle.sidebarWidth
            }.count
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return false }
            if paneCount == expected { return true }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: min(0.01, remaining)))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return false
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}

extension MacrosLayoutTests {
    func testClosingMacroPageLeavesBackgroundInputAvailable() {
        let suite = "JoyHarness.MacrosWindow.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        model.page = .macros
        let view = NSHostingView(rootView: DashboardView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsStyle.minimumWindowSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertFalse(model.recordingShortcut)
        window.close()
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(model.recordingShortcut)
    }
}
