import SwiftUI

struct ProfilesPage: View {
    @ObservedObject var model: DashboardModel
    let onNewProfile: () -> Void
    let onDuplicate: (UUID) -> Void
    @State private var deleting: KeyProfile?

    var body: some View {
        SettingsPanel {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                Label {
                    Text("全部方案").font(SettingsStyle.Typography.panelTitle)
                } icon: {
                    Image(systemName: "rectangle.3.group").foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button("管理绑定") { model.page = .harnesses }
                Button("新建方案", systemImage: "plus", action: onNewProfile)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAddProfile)
            }
            Text("同一方案可绑定多个 Harness，修改后对所有绑定的 Harness 生效。\n右键点按方案可设为默认方案。")
                .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.configuration.profiles) { profile in
                Divider()
                row(profile)
            }
        }
        .confirmationDialog("删除按键方案？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { profile in
            Button("删除方案", role: .destructive) { model.deleteProfile(profile.id); deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { profile in Text(deletionMessage(profile)) }
    }

    private func row(_ profile: KeyProfile) -> some View {
        let isDefault = profile.id == model.defaultProfile.id
        let bindings = model.configuration.harnesses.filter { $0.profileID == profile.id }
        return HStack(spacing: SettingsStyle.Spacing.controls) {
            Image(systemName: "keyboard").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(profile.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).help(profile.name)
                Text(bindingDescription(bindings, isDefault: isDefault))
                    .font(SettingsStyle.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if profile.id == model.selectedProfileID {
                SettingsStatus(title: "当前方案", color: .accentColor)
            }
            Button("编辑按键") { model.selectProfile(profile.id); model.page = .mapping }
            Button { onDuplicate(profile.id) } label: { Image(systemName: "plus.square.on.square") }
                .buttonStyle(.borderless)
                .disabled(!model.canAddProfile)
                .accessibilityLabel("复制「\(profile.name)」")
                .help("复制方案并重命名")
            if model.configuration.profiles.count > 1 {
                Button { deleting = profile } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("删除「\(profile.name)」")
                    .help("删除方案")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(isDefault ? "当前默认方案" : "设为默认方案") { model.setDefaultProfile(profile.id) }
                .disabled(isDefault)
        }
    }

    private func bindingDescription(_ bindings: [HarnessBinding], isDefault: Bool) -> String {
        let fallback = "未匹配 Harness 时使用"
        guard !bindings.isEmpty else { return isDefault ? fallback : "未绑定 Harness" }
        let names = bindings.map { $0.name + ($0.enabled ? "" : "（已停用）") }.joined(separator: "、")
        return "已绑定：" + names + (isDefault ? " · " + fallback : "")
    }

    private func deletionMessage(_ profile: KeyProfile) -> String {
        let bindings = model.configuration.harnesses.filter { $0.profileID == profile.id }
        let builtIns = bindings.filter(\.isBuiltIn).map(\.name)
        let custom = bindings.filter { !$0.isBuiltIn }.map(\.name)
        let fallback = profile.id == model.defaultProfile.id
            ? (model.configuration.profiles.first { $0.id != profile.id } ?? model.defaultProfile) : model.defaultProfile
        var lines = ["将删除「\(profile.name)」。"]
        if profile.id == model.defaultProfile.id { lines.append("默认方案将改为「\(fallback.name)」。") }
        if !builtIns.isEmpty { lines.append("\(builtIns.joined(separator: "、")) 将改用「\(fallback.name)」，启用状态保留。") }
        if !custom.isEmpty { lines.append("同时移除应用绑定：\(custom.joined(separator: "、"))。") }
        lines.append("此操作无法撤销。")
        return lines.joined(separator: "\n")
    }
}
