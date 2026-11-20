import AppKit
import XCTest
@testable import JoyHarness

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testDashboardKeepsMinimumContentSizeAcrossPages() throws {
        let suite = "JoyHarness.DashboardLayout.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        let size = SettingsStyle.minimumWindowSize
        let window = ApplicationDelegate.dashboardWindow(rootView: DashboardView(model: model), size: size)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView)
        window.orderFront(nil)

        for page in DashboardPage.allCases {
            model.page = page
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.bounds.size, size, "\(page) must fit the minimum content size")
        }
    }
}
