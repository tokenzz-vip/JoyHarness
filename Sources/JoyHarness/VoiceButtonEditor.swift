import SwiftUI

@MainActor
struct VoiceButtonEditor: View {
    @ObservedObject var model: DashboardModel
    let input: ControllerInput
    @Environment(\.dismiss) private var dismiss
    @State private var controllerID: String
    @State private var draft: VoiceButton

    init(model: DashboardModel, input: ControllerInput) {
        self.model = model
        self.input = input
        _controllerID = State(initialValue: model.controllerProfile.id)
        _draft = State(initialValue: model.voiceButton)
    }

    private var scopeMatches: Bool {
        controllerID == model.controllerProfile.id && model.voiceInput == input
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                Image(systemName: input.symbol)
                    .font(.system(size: 22)).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(input.label) · 语音模式").font(SettingsStyle.Typography.dialogTitle)
                    Text("固定语音触发 · 对当前手柄型号的所有方案和 Harness 生效")
                        .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(SettingsStyle.pagePadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
                    Text("两种模式分别绑定快捷键，请与语音工具的设置保持一致。")
                        .font(.callout).foregroundStyle(.secondary)

                    modeCard(.hold, detail: "按住说话，松手结束。", keys: Binding(
                        get: { [draft.holdKey] },
                        set: { if let key = $0.first { draft.holdKey = key } }
                    ))
                    modeCard(.tap, detail: "按一次开始说话，再按语音键结束，也可按其他手柄按键结束。", keys: $draft.tapKeys)

                    Text("点按模式需与语音工具的点按快捷键一致。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(SettingsStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if !scopeMatches {
                    Text("手柄或语音按键已更换，请重新打开编辑。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("mapping-editor-cancel")
                Button("保存") {
                    if model.saveVoiceButton(draft, controllerID: controllerID) { dismiss() }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("mapping-editor-save")
                .disabled(!scopeMatches)
            }
            .padding(.horizontal, SettingsStyle.pagePadding).padding(.vertical, 16)
        }
        .frame(width: 560, height: 560)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { model.beginEditing() }
        .onDisappear { model.endEditing() }
    }

    private func modeCard(_ mode: VoiceTriggerMode, detail: String, keys: Binding<Set<VoiceShortcutKey>>) -> some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
            HStack {
                Button { draft.mode = mode } label: {
                    Label(mode.title, systemImage: draft.mode == mode ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.mode == mode ? .isSelected : [])
                Spacer()
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            VoiceShortcutPicker(mode: mode, keys: keys)
            Text(mode == .hold ? "选择一个按键。" : "选择一个按键，或两个不同按键的组合。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(SettingsStyle.controlPadding)
        .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
    }
}
