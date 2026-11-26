import SwiftUI

/// Name entry for creating or renaming a key profile, with inline validation.
@MainActor
struct ProfileNameSheet: View {
    let title: String
    let symbol: String
    let confirmTitle: String
    @Binding var name: String
    var prefix: String = ""
    let validateName: (String) -> String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    // Sheet content can outlive the parent's render. Read the binding here so
    // the field, validation message and submit state always use the same draft.
    var error: String? { validateName(name) }
    var canConfirm: Bool {
        error == nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    if !prefix.isEmpty {
                        Text(prefix)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .help("遥控器固定前缀，不可修改或删除")
                            .accessibilityLabel("固定前缀 \(prefix)，不可修改或删除")
                    }
                    TextField("方案名称", text: $name)
                        .textFieldStyle(.plain)
                        .padding(SettingsStyle.compactControlPadding)
                        .onSubmit { if canConfirm { onConfirm() } }
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(SettingsActionButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(SettingsStyle.pagePadding)
        .frame(width: 420)
    }
}
