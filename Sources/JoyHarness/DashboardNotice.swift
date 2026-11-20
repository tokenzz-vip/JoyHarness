import SwiftUI

struct DashboardNotice: Identifiable {
    enum Level: String {
        case success, information, warning, error

        var title: String {
            switch self {
            case .success: "操作完成"
            case .information: "提示"
            case .warning: "需要处理"
            case .error: "操作失败"
            }
        }

        var autoDismissAfter: Duration? {
            switch self {
            case .success: .seconds(3)
            case .information: .seconds(5)
            case .warning, .error: nil
            }
        }

        var symbol: String {
            switch self {
            case .success: "checkmark.circle"
            case .information: "info.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var tint: Color {
            switch self {
            case .success: Color(nsColor: .systemGreen)
            case .information: Color(nsColor: .systemBlue)
            case .warning: Color(nsColor: .systemOrange)
            case .error: Color(nsColor: .systemRed)
            }
        }
    }

    enum Issue: Equatable {
        case configurationSave, login, export, importFile, recovery, clipboard
        case profileLimit, lastProfile, duplicateHarness(String)
        case macroLimit, macroName(UUID), macroSteps(UUID)
        case phraseDeletion(UUID), phraseUndo(UUID)
    }

    let id = UUID()
    let level: Level
    let detail: String
    let issue: Issue?
    let resolvedWhen: (@MainActor (DashboardModel) -> Bool)?
}

struct DashboardNoticeView: View {
    let notice: DashboardNotice
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.level.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(notice.level.tint)
                .frame(width: 20)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.level.title)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(notice.detail)
                    .font(SettingsStyle.Typography.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .help(notice.detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭提示")
            .accessibilityLabel("关闭\(notice.level.title)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(notice.level.tint.opacity(0.35))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 5)
        .accessibilityElement(children: .contain)
    }
}
