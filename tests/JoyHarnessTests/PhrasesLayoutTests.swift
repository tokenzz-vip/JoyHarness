import AppKit
import SwiftUI
import XCTest
@testable import JoyHarness

@MainActor
final class PhrasesLayoutTests: XCTestCase {
    func testMinimumWindowKeepsLibraryAndEditorInIndependentScrollAreas() throws {
        let suite = "JoyHarness.PhrasesLayoutTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        model.configuration.phrases += (0..<40).map { SavedPhrase(title: "更多常用语 \($0)", text: "测试内容") }
        model.page = .phrases
        let host = NSHostingView(rootView: DashboardView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsStyle.minimumWindowSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let panes = scrollViews(in: host).filter {
            $0.convert($0.bounds, to: host).minX > SettingsStyle.sidebarWidth
        }.sorted { $0.convert($0.bounds, to: host).minX < $1.convert($1.bounds, to: host).minX }
        XCTAssertEqual(panes.count, 2, "The phrase page must not have an outer scroll area")
        guard panes.count == 2 else { return }
        let list = panes[0]
        let editor = panes[1]
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        XCTAssertEqual(table.numberOfRows, 56)
        XCTAssertGreaterThan(table.bounds.height, list.contentView.bounds.height)
        let editorFrame = editor.convert(editor.bounds, to: host)
        XCTAssertGreaterThanOrEqual(editorFrame.minY, host.bounds.minY)
        XCTAssertLessThanOrEqual(editorFrame.maxY, host.bounds.maxY)
        XCTAssertGreaterThan(editorFrame.width, 250)
        XCTAssertGreaterThan(editorFrame.height, 300)
        list.contentView.scroll(to: CGPoint(x: 0, y: table.bounds.height - list.contentView.bounds.height))
        list.reflectScrolledClipView(list.contentView)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(list.contentView.bounds.minY, 0)
        XCTAssertEqual(editor.convert(editor.bounds, to: host), editorFrame)
        let boundWriter = table.dataSource?.tableView?(table, pasteboardWriterForRow: 0)
        let unboundWriter = table.dataSource?.tableView?(table, pasteboardWriterForRow: 5)
        XCTAssertNil(boundWriter, "Assigned rows stay fixed")
        XCTAssertNotNil(unboundWriter, "Unassigned rows support native dragging")
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
