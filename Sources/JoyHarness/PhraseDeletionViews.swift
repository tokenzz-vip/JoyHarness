import SwiftUI

@MainActor
struct PhraseDeletionConfirmationSheet: View {
    @ObservedObject var model: DashboardModel
    let pending: PendingPhraseDeletion
    private var current: PendingPhraseDeletion { model.pendingPhraseDeletion ?? pending }

    var body: some View {
        let deletion = current
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.sections) {
            Text("删除「\(deletion.name)」？")
                .font(SettingsStyle.Typography.dialogTitle).lineLimit(2)
            Text("该项目正在被使用，删除将影响以下配置。")
                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                Text("\(deletion.assignments.count) 个五向分配将解除")
                    .font(.system(size: 13, weight: .semibold))
                Text(deletion.assignments.map(\.label).joined(separator: "、"))
                    .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(SettingsStyle.panelPadding)
            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
            Text("删除后可在窗口底部撤销，恢复原内容、顺序及五向分配。")
                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消") { model.pendingPhraseDeletion = nil }.keyboardShortcut(.cancelAction)
                Button("仍然删除", role: .destructive) { model.confirmPhraseDeletion(deletion.id) }
            }
        }
        .padding(SettingsStyle.pagePadding).frame(width: 528)
    }
}

@MainActor
struct PhraseDeletionUndoBar: View {
    @ObservedObject var model: DashboardModel
    let deleted: DeletedPhrase

    var body: some View {
        HStack(spacing: SettingsStyle.Spacing.controls) {
            Text("已删除「\(deleted.phrase.displayTitle)」")
                .font(SettingsStyle.Typography.body).lineLimit(1).truncationMode(.middle)
                .help(deleted.phrase.displayTitle)
            Spacer(minLength: 12)
            Button("撤销删除") { model.undoPhraseDeletion() }
                .controlSize(.small)
                .help("恢复最近删除的常用语、顺序及分配；本次运行内可连续撤销")
            Button { model.phraseDeletionUndoStack.removeAll() } label: {
                Image(systemName: "xmark").font(SettingsStyle.Typography.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("关闭删除撤销提示").accessibilityLabel("关闭删除撤销提示")
        }
        .padding(.horizontal, SettingsStyle.pagePadding).padding(.vertical, 12)
        .background(SettingsStyle.subtle)
        .overlay(alignment: .top) { Divider() }
    }
}
