import AppKit
import XCTest
@testable import JoyHarness

@MainActor
final class DashboardLayoutTests: XCTestCase {
    func testDashboardImmediatelyResumesInheritingAppearance() throws {
        let suite = "JoyHarness.DashboardAppearance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let app = NSApplication.shared
        let previousAppearance = app.appearance
        defer {
            app.appearance = previousAppearance
            defaults.removePersistentDomain(forName: suite)
        }
        app.appearance = nil
        let systemAppearance = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        defaults.set(AppThemeMode.dark.rawValue, forKey: "JoyHarness.theme")
        let model = DashboardModel(defaults: defaults, preview: true)
        model.page = .settings
        let window = ApplicationDelegate.dashboardWindow(rootView: HarnessRootView(model: model, setup: model.setup))
        defer { window.close() }
        let themeSubscription = ApplicationDelegate.bindTheme(to: model)
        defer { themeSubscription.cancel() }
        window.orderFront(nil)

        func expectAppearance(_ name: NSAppearance.Name?, line: UInt = #line) {
            let appearances = [window.effectiveAppearance, window.contentView?.effectiveAppearance]
            for appearance in appearances {
                XCTAssertEqual(appearance?.bestMatch(from: [.aqua, .darkAqua]), name, line: line)
            }
        }

        expectAppearance(.darkAqua)
        XCTAssertEqual(app.appearance?.name, .darkAqua)
        model.themeMode = .system
        XCTAssertNil(app.appearance)
        expectAppearance(systemAppearance)
        model.themeMode = .light
        expectAppearance(.aqua)
        XCTAssertEqual(app.appearance?.name, .aqua)
        model.themeMode = .system
        XCTAssertNil(app.appearance)
        expectAppearance(systemAppearance)
    }

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
