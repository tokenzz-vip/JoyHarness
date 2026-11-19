import Foundation
import Testing
@testable import JoyHarness

struct StatisticsTests {
    @Test func rangesUseLocalCalendarAndApplyToAllMetrics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: .init(year: 2026, month: 11, day: 16, hour: 1))!
        let statistics = UsageStatistics(days: ["2026-11-16": ["a": 2], "2026-11-10": ["b": 3],
                                               "2026-11-09": ["a": 10], "2026-11-17": ["a": 100]])
        let today = StatisticsSummary(statistics: statistics, range: .day, now: now, calendar: calendar)
        #expect(today.total == 2); #expect(today.activeDays == 1); #expect(today.days.count == 1)
        let week = StatisticsSummary(statistics: statistics, range: .lastSevenDays, now: now, calendar: calendar)
        #expect(week.total == 5); #expect(week.activeDays == 2); #expect(week.ranking.first?.key == "b")
        let all = StatisticsSummary(statistics: statistics, range: .all, now: now, calendar: calendar)
        #expect(all.total == 15); #expect(all.activeDays == 3)
        #expect(all.days.map(\.id) == ["2026-11-09", "2026-11-10", "2026-11-16"])
    }
}
