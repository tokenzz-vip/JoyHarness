import Charts
import SwiftUI

enum StatisticsRange: String, CaseIterable, Identifiable {
    case day, lastSevenDays, all
    var id: String { rawValue }
    var title: String { switch self { case .day: "今天"; case .lastSevenDays: "最近 7 天"; case .all: "全部" } }
}

struct StatisticsSummary {
    struct Day: Identifiable {
        let id: String
        let date: Date
        let count: Int
    }
    let days: [Day]
    let ranking: [(key: String, value: Int)]
    var total: Int { ranking.reduce(0) { $0 + $1.value } }
    var activeDays: Int { days.filter { $0.count > 0 }.count }
    init(statistics: UsageStatistics, range: StatisticsRange, now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start: Date? = switch range {
        case .day: today
        case .lastSevenDays: calendar.date(byAdding: .day, value: -6, to: today)
        case .all: nil
        }
        var days: [Day] = [], counts: [String: Int] = [:]
        for (key, inputs) in statistics.days {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  date <= today, start == nil || date >= start! else { continue }
            days.append(.init(id: key, date: date, count: inputs.values.reduce(0, +)))
            for (input, value) in inputs { counts[input, default: 0] += value }
        }
        self.days = days.sorted { $0.date < $1.date }
        ranking = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }
}

struct StatisticsPage: View {
    @Environment(\.appColorMode) private var colorMode
    private struct RankingEntry: Identifiable {
        let rank: Int
        let key: String
        let value: Int
        var id: String { key }
    }

    let statistics: UsageStatistics
    let range: StatisticsRange
    var body: some View {
        let summary = StatisticsSummary(statistics: statistics, range: range)
        VStack(alignment: .leading, spacing: 16) {
            Text("统计汇总所有手柄，同名按键合并计数。")
                .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                metric("按键总次数", symbol: "keyboard", value: "\(summary.total)")
                metric("使用天数", symbol: "calendar", value: "\(summary.activeDays)")
                metric("最常用按键", symbol: "sparkle", value: summary.ranking.first.map { ControllerInput(rawValue: $0.key)?.label ?? $0.key } ?? "—")
            }
            if summary.total == 0 {
                SettingsPanel {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar").font(.system(size: 32)).foregroundStyle(.tertiary)
                        Text("此时间范围内还没有使用记录").font(.headline)
                        Text("使用选中的手柄后，这里会显示次数、趋势和排行。统计仅保存在这台 Mac。")
                            .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 35)
                }
            } else {
                SettingsPanel("每日按键次数", symbol: "chart.bar") {
                    Chart(summary.days) { day in
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value("按键次数", day.count))
                            .foregroundStyle(colorMode.palette.selectionTint).cornerRadius(3)
                    }.frame(height: 185)
                        .accessibilityLabel("\(range.title)按键次数趋势，共 \(summary.total) 次")
                }
                SettingsPanel("按键使用排行 · 全部按键", symbol: "chart.bar.xaxis") {
                    let rankedEntries = summary.ranking.enumerated().map {
                        RankingEntry(rank: $0.offset + 1, key: $0.element.key, value: $0.element.value)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: SettingsStyle.Spacing.sections)], spacing: 0) {
                        ForEach(rankedEntries) { entry in
                            rankingRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func rankingRow(_ entry: RankingEntry) -> some View {
        HStack(spacing: SettingsStyle.Spacing.inline) {
            Text("\(entry.rank)")
                .font(SettingsStyle.Typography.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(entry.rank <= 3 ? colorMode.palette.selectionTint : .secondary)
                .frame(width: 20, alignment: .leading)
            Text(ControllerInput(rawValue: entry.key)?.label ?? entry.key)
                .font(SettingsStyle.Typography.body)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text("\(entry.value) 次")
                .font(SettingsStyle.Typography.body).monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 28)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .foregroundStyle(colorMode.palette.selectionTint)
                    .accessibilityHidden(true)
            }
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(SettingsStyle.panelPadding)
            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
            .overlay { RoundedRectangle(cornerRadius: SettingsStyle.panelRadius).strokeBorder(Color.primary.opacity(0.07)) }
    }
}
