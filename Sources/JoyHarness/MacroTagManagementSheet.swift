import SwiftUI

@MainActor
struct MacroTagManagementSheet: View {
    private enum Page {
        case catalog
        case edit(MacroTag?)
        case delete(MacroTag)
    }

    @ObservedObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var page = Page.catalog
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
            switch page {
            case .catalog: catalog
            case .edit(let tag): nameEditor(tag)
            case .delete(let tag): deletionConfirmation(tag)
            }
        }
        .font(SettingsStyle.Typography.body)
        .padding(SettingsStyle.pagePadding)
        .frame(width: 440)
    }

    private var catalog: some View {
        Group {
            Text("管理标签").font(SettingsStyle.Typography.dialogTitle)
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    Text("内置标签").font(SettingsStyle.Typography.panelTitle)
                    Label("只读", systemImage: "lock")
                        .font(SettingsStyle.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), alignment: .leading)],
                          alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                    ForEach(MacroTag.all) { tag in
                        Text(tag.name)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Divider()
            HStack {
                Text("自定义标签").font(SettingsStyle.Typography.panelTitle)
                Spacer()
                Button { edit(nil) } label: { Label("新建标签", systemImage: "plus") }
            }
            if model.customMacroTags.isEmpty {
                Text("暂无自定义标签")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, SettingsStyle.Spacing.inline)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.customMacroTags) { tag in
                            tagRow(tag)
                            if tag.id != model.customMacroTags.last?.id { Divider() }
                        }
                    }
                    .padding(.trailing, SettingsStyle.Spacing.inline)
                }
                .frame(height: min(240, CGFloat(model.customMacroTags.count) * 34))
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func tagRow(_ tag: MacroTag) -> some View {
        HStack(spacing: SettingsStyle.Spacing.inline) {
            Text(tag.name).lineLimit(1).help(tag.name)
            Spacer(minLength: 4)
            Button("改名") { edit(tag) }
                .accessibilityLabel("修改「\(tag.name)」名称")
            Button("删除…", role: .destructive) {
                error = nil
                page = .delete(tag)
            }
            .accessibilityLabel("删除「\(tag.name)」")
        }
        .controlSize(.small)
        .frame(height: 33)
    }

    private func edit(_ tag: MacroTag?) {
        name = tag?.name ?? ""
        error = nil
        page = .edit(tag)
    }

    private func nameEditor(_ tag: MacroTag?) -> some View {
        Group {
            Text(tag == nil ? "新建标签" : "修改标签名称").font(SettingsStyle.Typography.dialogTitle)
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                Text("标签名称")
                TextField("标签名称", text: $name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
                    .onChange(of: name) { _, _ in error = nil }
                errorMessage
            }
            HStack {
                Spacer()
                cancelButton
                Button("保存") {
                    do {
                        try model.saveCustomMacroTag(name: name, id: tag?.id)
                        page = .catalog
                    } catch {
                        self.error = error.localizedDescription
                        nameFocused = true
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func deletionConfirmation(_ tag: MacroTag) -> some View {
        let count = model.savedMacros.count { $0.tagIDs.contains(tag.id) }
        return Group {
            Text("删除「\(tag.name)」？")
                .font(SettingsStyle.Typography.dialogTitle)
                .lineLimit(2)
                .help(tag.name)
            Text(count > 0 ? "将从 \(count) 个组合动作中移除此标签，动作及按键绑定会保留。" : "目前没有组合动作使用此标签。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            errorMessage
            HStack {
                Spacer()
                cancelButton
                Button("删除标签", role: .destructive) {
                    do {
                        try model.deleteCustomMacroTag(tag.id)
                        page = .catalog
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    private var cancelButton: some View {
        Button("取消") { page = .catalog }.keyboardShortcut(.cancelAction)
    }

    @ViewBuilder private var errorMessage: some View {
        if let error {
            Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }
}
