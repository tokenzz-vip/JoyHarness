import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct DashboardNoticeTests {
    @Test func transientNoticesExpireWhileIssuesStayVisible() async throws {
        let suite = "JoyHarness.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let successModel = DashboardModel(defaults: defaults, preview: true)
        let infoModel = DashboardModel(defaults: defaults, preview: true)
        successModel.showNotice(.warning, "需要处理", issue: .lastProfile)
        successModel.showNotice(.success, "已导出配置")
        infoModel.showNotice(.error, "无法导入", issue: .importFile)
        infoModel.showNotice(.information, "当前使用方向映射")

        try await Task.sleep(for: .milliseconds(3500))
        #expect(successModel.notices.map(\.level) == [.warning])
        #expect(infoModel.notices.map(\.level) == [.error, .information])

        try await Task.sleep(for: .seconds(2))
        #expect(infoModel.notices.map(\.level) == [.error])
        let error = try #require(infoModel.notices.first)
        infoModel.dismissNotice(error.id)
        #expect(infoModel.notices.isEmpty)
    }
}
