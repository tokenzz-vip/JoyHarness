import AppKit
import SwiftUI

struct ProfilesPage: View {
    @Environment(\.appColorMode) private var colorMode
    @ObservedObject var model: DashboardModel
    let onNewProfile: () -> Void
    let onDuplicate: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var browsingID: UUID?
    @State private var deleting: KeyProfile?

    private var profiles: [KeyProfile] { model.configuration.profiles }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matchingProfiles(bindings: [UUID: [HarnessBinding]]) -> [KeyProfile] {
        guard !searchTerm.isEmpty else { return profiles }
        return profiles.filter { profile in
            profile.name.localizedStandardContains(searchTerm) ||
                (bindings[profile.id] ?? []).contains { $0.name.localizedStandardContains(searchTerm) }
        }
    }
    private func browsingIndex(in profiles: [KeyProfile]) -> Int {
        profiles.firstIndex { $0.id == browsingID } ??
            profiles.firstIndex { $0.id == model.selectedProfileID } ?? 0
    }

    var body: some View {
        let bindings = Dictionary(grouping: model.configuration.harnesses, by: \.profileID)
        let results = matchingProfiles(bindings: bindings)
        let index = browsingIndex(in: results)
        SettingsWorkspace {
            library(results, selectedID: results.isEmpty ? nil : results[index].id, bindings: bindings)
        } detail: {
            if results.isEmpty {
                SettingsEmpty(symbol: "magnifyingglass", title: "没有匹配的方案", detail: "试试其他方案名或应用名。")
                    .padding(SettingsStyle.pagePadding)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
                        coverFlow(results, at: index, bindings: bindings)
                        let profile = results[index]
                        details(profile, bindings: bindings[profile.id] ?? [])
                    }
                    .padding(SettingsStyle.pagePadding)
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .confirmationDialog("删除按键方案？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { profile in
            Button("删除方案", role: .destructive) {
                model.deleteProfile(profile.id)
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { profile in Text(deletionMessage(profile)) }
    }

    private func library(_ results: [KeyProfile], selectedID: UUID?, bindings: [UUID: [HarnessBinding]]) -> some View {
        VStack(spacing: 0) {
            SettingsLibraryHeader(title: "全部方案") {
                Button(action: onNewProfile) { Image(systemName: "plus").frame(width: 20) }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(!model.canAddProfile)
                    .accessibilityLabel("新建方案")
                    .help(model.canAddProfile ? "新建方案" : "已达到自定义方案上限")
            }
            SettingsSearchField(prompt: "搜索方案或应用", query: $query)
                .padding(.horizontal, SettingsStyle.Spacing.groups)
                .padding(.bottom, SettingsStyle.Spacing.controls)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { profile in
                            libraryRow(profile, selected: profile.id == selectedID, bindings: bindings[profile.id] ?? [])
                                .id(profile.id)
                        }
                    }
                    .padding(SettingsStyle.Spacing.inline)
                }
                .onChange(of: selectedID, initial: true) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func libraryRow(_ profile: KeyProfile, selected: Bool, bindings: [HarnessBinding]) -> some View {
        let isDefault = profile.id == model.defaultProfile.id
        return Button {
            browsingID = profile.id
        } label: {
            HStack(spacing: SettingsStyle.Spacing.inline) {
                let symbol = bindings.isEmpty ? "keyboard" : "app"
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(SettingsStyle.Typography.listTitle)
                        .lineLimit(1)
                    Text(bindingSummary(bindings))
                        .font(SettingsStyle.Typography.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isDefault {
                    Text("默认")
                        .font(SettingsStyle.Typography.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, SettingsStyle.Spacing.inline)
            .frame(minHeight: 52)
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
        }
        .buttonStyle(SettingsSidebarRowStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(profile.name)
        .contextMenu {
            Button(isDefault ? "当前默认方案" : "设为默认方案") { model.setDefaultProfile(profile.id) }
                .disabled(isDefault)
        }
    }

    private func coverFlow(_ profiles: [KeyProfile], at index: Int, bindings: [UUID: [HarnessBinding]]) -> some View {
        let visible = max(0, index - 1)...min(profiles.count - 1, index + 1)
        return VStack(spacing: SettingsStyle.Spacing.groups) {
            ZStack {
                ForEach(profiles[visible]) { profile in
                    let distance = (profiles.firstIndex { $0.id == profile.id } ?? index) - index
                    cover(profile, binding: bindings[profile.id]?.first, selected: distance == 0)
                        .onKeyPress(.leftArrow) { step(-1, in: profiles) }
                        .onKeyPress(.rightArrow) { step(1, in: profiles) }
                        .scaleEffect(x: distance == 0 ? 1 : 0.77, y: distance == 0 ? 1 : 0.84)
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(distance) * 8))
                        .offset(x: CGFloat(distance) * 134)
                        .zIndex(distance == 0 ? 1 : 0)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: profiles[index].id)

            HStack(spacing: SettingsStyle.Spacing.controls) {
                stepButton(-1, in: profiles, at: index)
                Text("\(index + 1) / \(profiles.count)")
                    .font(SettingsStyle.Typography.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 62)
                    .accessibilityLabel("第 \(index + 1) 个方案，共 \(profiles.count) 个")
                stepButton(1, in: profiles, at: index)
            }
        }
        .padding(.vertical, SettingsStyle.Spacing.sections)
        .frame(maxWidth: .infinity)
        .background(colorMode.palette.selectionBackground.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsStyle.panelRadius)
                .strokeBorder(SettingsStyle.workspaceDivider)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("方案预览")
    }

    private func cover(_ profile: KeyProfile, binding: HarnessBinding?, selected: Bool) -> some View {
        Button {
            browsingID = profile.id
        } label: {
            VStack(spacing: SettingsStyle.Spacing.controls) {
                coverIcon(binding)
                    .frame(width: 60, height: 60)
                    .background(colorMode.palette.selectionBackground,
                                in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
                    .accessibilityHidden(true)
                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, SettingsStyle.Spacing.controls)
            .frame(width: 156, height: 156)
            .background(SettingsStyle.pageBackground, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsStyle.panelRadius)
                    .strokeBorder(selected ? colorMode.palette.selectionTint.opacity(0.64)
                                  : SettingsStyle.workspaceDivider, lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(selected ? 0.10 : 0.04), radius: 8, y: 4)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(profile.name)
    }

    @ViewBuilder
    private func coverIcon(_ binding: HarnessBinding?) -> some View {
        if let url = binding?.installedApplicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 46, height: 46)
        } else if binding != nil {
            HarnessIcon(size: 30)
                .foregroundStyle(colorMode.palette.selectionTint)
        } else {
            Image(systemName: "keyboard")
                .font(.system(size: 29, weight: .regular))
                .foregroundStyle(colorMode.palette.selectionTint)
        }
    }

    private func stepButton(_ direction: Int, in profiles: [KeyProfile], at index: Int) -> some View {
        let previous = direction < 0
        let title = previous ? "上一个方案" : "下一个方案"
        return Button {
            _ = step(direction, in: profiles)
        } label: {
            Image(systemName: previous ? "chevron.left" : "chevron.right")
                .frame(width: 22)
        }
        .buttonStyle(SettingsActionButtonStyle())
        .disabled(!profiles.indices.contains(index + direction))
        .accessibilityLabel(title)
        .help(title)
        .onKeyPress(.leftArrow) { step(-1, in: profiles) }
        .onKeyPress(.rightArrow) { step(1, in: profiles) }
    }

    private func step(_ direction: Int, in profiles: [KeyProfile]) -> KeyPress.Result {
        let next = browsingIndex(in: profiles) + direction
        guard profiles.indices.contains(next) else { return .handled }
        browsingID = profiles[next].id
        return .handled
    }

    private func details(_ profile: KeyProfile, bindings: [HarnessBinding]) -> some View {
        let isDefault = profile.id == model.defaultProfile.id
        return SettingsPanel {
            HStack(alignment: .top, spacing: SettingsStyle.Spacing.controls) {
                Text(profile.name)
                    .font(SettingsStyle.Typography.dialogTitle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if isDefault {
                    SettingsStatus(title: "默认", color: colorMode.palette.selectionTint)
                        .help("未匹配 Harness 时使用")
                }
                if profile.id == model.selectedProfileID {
                    SettingsStatus(title: "当前编辑")
                }
            }
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: SettingsStyle.Spacing.controls) {
                Label("绑定应用", systemImage: "link")
                    .font(SettingsStyle.Typography.body.weight(.semibold))
                    .fixedSize()
                Text(bindingSummary(bindings))
                    .font(SettingsStyle.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("管理绑定") { model.page = .harnesses }
                    .buttonStyle(SettingsActionButtonStyle())
            }
            if isDefault {
                Text("前台应用未匹配 Harness 时使用此方案。")
                    .font(SettingsStyle.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: SettingsStyle.Spacing.controls) {
                Button("设为默认") { model.setDefaultProfile(profile.id) }
                    .disabled(isDefault)
                Button("复制方案") { onDuplicate(profile.id) }
                    .disabled(!model.canAddProfile)
                if profiles.count > 1 {
                    Button("删除方案…") { deleting = profile }
                }
                Spacer(minLength: 0)
                Button("编辑按键", systemImage: "pencil") {
                    model.selectProfile(profile.id)
                    model.page = .mapping
                }
                .buttonStyle(SettingsActionButtonStyle(prominent: true))
            }
            .buttonStyle(SettingsActionButtonStyle())
        }
    }

    private func bindingSummary(_ bindings: [HarnessBinding]) -> String {
        guard !bindings.isEmpty else { return "未绑定应用" }
        return bindings.map { $0.name + ($0.enabled ? "" : "（已停用）") }.joined(separator: "、")
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
