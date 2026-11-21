import SwiftUI

struct GlobalButtonsPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        SettingsPanel("全局按键 · \(model.controllerProfile.name)", symbol: "globe") {
            Text("全局按键对当前手柄型号的所有方案和 Harness 生效。普通全局按键的第一项必选，动作在「按键映射」中编辑，未覆盖的手势沿用方案动作。")
                .font(SettingsStyle.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SettingsStyle.Spacing.inline) {
                Label("语音按键", systemImage: "mic")
                    .font(SettingsStyle.Typography.body.weight(.medium))
                    .frame(width: 180, alignment: .leading)
                Spacer(minLength: 0)
                Picker("语音按键", selection: Binding(get: { model.voiceInput }, set: model.setVoiceInput)) {
                    Text("未设置").tag(nil as ControllerInput?)
                    ForEach(model.voiceInputChoices) { input in
                        Text(input.label).tag(Optional(input))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                Color.clear.frame(width: 24, height: 24).accessibilityHidden(true)
            }
            Divider()

            ForEach(Array(model.globalButtons.enumerated()), id: \.element.id) { index, button in
                let name = button.input?.label ?? "未设置按键"
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    Label(name, systemImage: button.input?.symbol ?? "questionmark.circle")
                        .font(SettingsStyle.Typography.body.weight(.medium))
                        .foregroundStyle(button.input == nil ? .secondary : .primary)
                        .frame(width: 180, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("全局按键 \(index + 1)", selection: Binding<ControllerInput?>(
                        get: { model.globalButtons.first { $0.id == button.id }?.input },
                        set: { model.setGlobalInput($0, for: button.id) }
                    )) {
                        if index > 0 { Text("未设置").tag(nil as ControllerInput?) }
                        ForEach(model.globalInputChoices(for: button.id)) { input in
                            Text(input.label).tag(Optional(input))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .help(index == 0 ? "第一项必须设置" : "选择按键，或留空")
                    if index > 0 {
                        Button(role: .destructive) { model.removeGlobalButton(button.id) } label: {
                            Image(systemName: "trash").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("删除全局按键：\(name)")
                        .help("删除此全局按键")
                    } else {
                        Color.clear.frame(width: 24, height: 24).accessibilityHidden(true)
                    }
                }
            }

            Button(action: model.addGlobalButton) {
                Label("增加全局按键", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
    }
}
