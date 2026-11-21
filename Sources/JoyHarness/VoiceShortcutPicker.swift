import SwiftUI

struct VoiceShortcutPicker: View {
    let mode: VoiceTriggerMode
    @Binding var keys: Set<VoiceShortcutKey>
    @State private var isPresented = false
    @State private var hovering = false

    var body: some View {
        let shortcut = VoiceShortcut(mode: mode, keys: keys)
        HStack(spacing: SettingsStyle.Spacing.controls) {
            Text("快捷键").font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Button { isPresented.toggle() } label: {
                HStack(spacing: 6) {
                    ForEach(Array(shortcut.orderedKeys.enumerated()), id: \.element) { index, key in
                        if index != 0 { Text("+").foregroundStyle(.tertiary) }
                        Text(key.pickerLabel)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isPresented ? 180 : 0))
                        .animation(.easeOut(duration: 0.16), value: isPresented)
                }
                .padding(.horizontal, SettingsStyle.controlPadding)
                .frame(height: 36)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsStyle.controlRadius)
                        .strokeBorder(isPresented ? Color.accentColor : Color.primary.opacity(hovering ? 0.22 : 0.12))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(mode == .hold ? "长按快捷键" : "点按快捷键")
            .accessibilityValue(shortcut.label)
            .accessibilityHint("打开按键选择面板")
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VoiceShortcutSelectionPanel(mode: mode, selection: keys) { selection in
                    if let selection { keys = selection }
                    isPresented = false
                }
            }
        }
    }
}

struct VoiceShortcutSelectionPanel: View {
    let mode: VoiceTriggerMode
    let close: (Set<VoiceShortcutKey>?) -> Void
    @State private var selection: Set<VoiceShortcutKey>
    @Environment(\.colorScheme) private var colorScheme

    init(mode: VoiceTriggerMode, selection: Set<VoiceShortcutKey>, close: @escaping (Set<VoiceShortcutKey>?) -> Void) {
        self.mode = mode
        self.close = close
        _selection = State(initialValue: selection)
    }

    private var maximumKeys: Int { mode == .hold ? 1 : 2 }
    private var selectionHint: String {
        if mode == .hold { return "选择一个按键，点击其他按键即可更换" }
        return selection.count == maximumKeys ? "已选满两个按键，先取消一个即可更换" : "选择一个或两个按键，再次点击可取消"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .hold ? "长按快捷键" : "点按快捷键").font(SettingsStyle.Typography.dialogTitle)
                Text(selectionHint).font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Divider()
            ScrollView {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow { keyButton(.function).gridCellColumns(2) }
                    GridRow {
                        keyButton(.leftCommand)
                        keyButton(.rightCommand)
                    }
                    GridRow {
                        keyButton(.leftOption)
                        keyButton(.rightOption)
                    }
                    GridRow {
                        keyButton(.leftControl)
                        keyButton(.rightControl)
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: SettingsStyle.Spacing.inline) {
                Text("已选 \(selection.count) / \(maximumKeys)")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("取消") { close(nil) }.keyboardShortcut(.cancelAction)
                Button("使用快捷键") { close(selection) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 360, height: 344)
        .background(SettingsStyle.shortcutPopoverBackground(in: colorScheme))
    }

    private func keyButton(_ key: VoiceShortcutKey) -> some View {
        VoiceShortcutKeyButton(key: key, selected: selection.contains(key)) {
            if mode == .hold { selection = [key] }
            else if selection.contains(key) { selection.remove(key) }
            else { selection.insert(key) }
        }
        .disabled(mode == .tap && selection.count == maximumKeys && !selection.contains(key))
    }
}

private struct VoiceShortcutKeyButton: View {
    let key: VoiceShortcutKey
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var background: Color {
        if selected { return Color.accentColor.opacity(colorScheme == .dark ? 0.19 : 0.08) }
        return hovering && isEnabled ? Color.primary.opacity(0.075) : SettingsStyle.subtle
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(key.glyph)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                Text(key == .function ? "地球键" : key.label.replacingOccurrences(of: "侧", with: ""))
                    .font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .opacity(selected ? 1 : 0).frame(width: 12)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(background, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(key.label)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .help(isEnabled ? key.label : "最多选择两个按键，先取消一个已选按键即可更换")
    }
}

private extension VoiceShortcutKey {
    var glyph: String {
        switch self {
        case .function: "fn"
        case .leftCommand, .rightCommand: "⌘"
        case .leftOption, .rightOption: "⌥"
        case .leftControl, .rightControl: "⌃"
        }
    }

    var pickerLabel: String {
        self == .function ? "Fn / 地球键" : "\(label.hasPrefix("左") ? "左" : "右")侧 \(glyph)"
    }
}
