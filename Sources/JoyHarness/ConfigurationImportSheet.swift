import SwiftUI

@MainActor
struct ConfigurationImportSheet: View {
    @ObservedObject var model: DashboardModel
    let preview: ConfigurationImportPreview
    @State private var errorMessage: String?

    var body: some View {
        let current = model.configuration
        let next = preview.configuration
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.sections) {
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                Text(preview.isRecovery ? "恢复替换前配置" : "导入配置")
                    .font(SettingsStyle.Typography.dialogTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(preview.source).font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(preview.source)
            }
            Grid(alignment: .leading, horizontalSpacing: SettingsStyle.Spacing.sections, verticalSpacing: 10) {
                GridRow {
                    Text("替换范围")
                    Text("当前").gridColumnAlignment(.trailing)
                    Text(preview.isRecovery ? "恢复后" : "导入后").gridColumnAlignment(.trailing)
                }.font(SettingsStyle.Typography.caption.weight(.medium)).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                countRow("全局按键", current.globalButtons.values.flatMap { $0 }.compactMap(\.input).count,
                         next.globalButtons.values.flatMap { $0 }.compactMap(\.input).count)
                countRow("键位方案", current.profiles.count, next.profiles.count)
                countRow("Harness 应用及绑定", current.harnesses.count, next.harnesses.count)
                countRow("组合动作", current.macros.count, next.macros.count)
                countRow("常用语", current.phrases.count, next.phrases.count)
                countRow("五向分配", current.phraseAssignments.slots.count, next.phraseAssignments.slots.count)
                countRow("摇杆校准记录", current.centers.count, next.centers.count)
            }
            .padding(SettingsStyle.panelPadding)
            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
            Text("摇杆死区和指针速度也会替换。每次替换自动保留最近一份配置，重启后仍可恢复。")
                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage).font(SettingsStyle.Typography.body).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { model.pendingConfigurationImport = nil }
                    .keyboardShortcut(.cancelAction)
                Button(preview.isRecovery ? "恢复配置" : "替换配置") {
                    do { try model.confirmConfigurationImport(preview.id) }
                    catch { errorMessage = "无法替换配置。\(error.localizedDescription)" }
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(SettingsStyle.pagePadding)
        .frame(width: 528)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func countRow(_ title: String, _ current: Int, _ next: Int) -> some View {
        GridRow {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(current)").foregroundStyle(.secondary)
            Text("\(next)").fontWeight(.medium)
        }.font(SettingsStyle.Typography.body).monospacedDigit()
    }
}
