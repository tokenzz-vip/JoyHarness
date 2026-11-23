import AppKit
import SwiftUI

/// The same field geometry and controls as RcHarness's action editor.
@MainActor
struct MappingEditorField<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        HStack(spacing: SettingsStyle.Spacing.inline) {
            Text(title).frame(width: 52, alignment: .leading).accessibilityHidden(true)
            content.labelsHidden().frame(maxWidth: .infinity)
        }.font(SettingsStyle.Typography.body)
    }
}

struct MacroActionEditor: View {
    @Binding private var value: ButtonMapping
    @ObservedObject var model: DashboardModel
    let parentMacroID: UUID
    @State private var draft: ButtonMapping
    @Binding var keyboardShortcut: Binding<RecordedShortcut?>?
    @State private var selectedMacroTagIDs: Set<String> = []

    init(value: Binding<ButtonMapping>, model: DashboardModel, parentMacroID: UUID,
         keyboardShortcut: Binding<Binding<RecordedShortcut?>?>) {
        _value = value; self.model = model; self.parentMacroID = parentMacroID
        _keyboardShortcut = keyboardShortcut
        _draft = State(initialValue: value.wrappedValue)
    }

    private var actions: [RemoteAction] {
        let basic: [RemoteAction] = [.enter, .backspace, .escape, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .copy, .paste, .browserBack, .browserForward]
        let system: [RemoteAction] = [.volumeUp, .volumeDown, .mute, .playPause] + RemoteAction.harnessFocusActions + [
            .scrollUp, .scrollDown]
        let custom: [RemoteAction] = [.recordedShortcut, .openApplication, .phrase, .macro]
        var ordered: [RemoteAction] = [.disabled] + custom + basic + system
        if draft.action.canRunInMacro, !draft.action.isLegacyPointerAction, !ordered.contains(draft.action) {
            ordered.append(draft.action)
        }
        return ordered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
            MappingEditorField("执行动作") {
                SettingsSingleSelectionPicker(selection: Binding(get: { draft.action }, set: { draft = .init(action: $0) }),
                    options: actions.map { SettingsSelectionOption(value: $0, title: actionTitle($0)) },
                    accessibilityLabel: "执行动作", identifier: "mapping-action-picker",
                    missingSelectionTitle: actionTitle(draft.action))
            }
            if draft.action == .recordedShortcut {
                ShortcutBindingEditor(shortcut: $draft.shortcut, keyboardShortcut: $keyboardShortcut) { active in
                    if active { model.beginEditing() } else { model.endEditing() }
                }
            }
            if draft.action == .openApplication {
                HStack {
                    Text(draft.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "尚未选择 App")
                        .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                    Spacer()
                    Button("选择 App…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK { draft.applicationPath = panel.url?.path }
                    }
                }
            }
            if draft.action == .phrase {
                MappingEditorField("常用语") {
                    SettingsSingleSelectionPicker(selection: Binding(
                        get: { model.configuration.phrases.first(where: { $0.text == draft.text })?.id.uuidString ?? (draft.text?.isEmpty == false ? "custom" : "") },
                        set: { id in draft.text = model.configuration.phrases.first(where: { $0.id.uuidString == id })?.text }
                    ), options: [SettingsSelectionOption(value: "", title: "选择常用语")] + model.configuration.phrases.map {
                        SettingsSelectionOption(value: $0.id.uuidString, title: $0.displayTitle)
                    }, accessibilityLabel: "常用语", identifier: "mapping-phrase-picker", missingSelectionTitle: "自定义文本")
                }
                if let text = draft.text, !text.isEmpty, !model.configuration.phrases.contains(where: { $0.text == text }) {
                    TextEditor(text: Binding(get: { draft.text ?? "" }, set: { draft.text = $0 }))
                        .font(SettingsStyle.Typography.body).frame(height: 80)
                        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)) }
                }
                Button("管理常用语") { model.page = .phrases }.buttonStyle(.link).font(.caption)
            }
            if draft.action == .macro {
                MacroReferencePicker(referenceID: Binding(get: { draft.macroID?.uuidString }, set: { draft.macroID = $0.flatMap(UUID.init(uuidString:)) }),
                    tagIDs: $selectedMacroTagIDs, model: model, parentMacroID: parentMacroID)
            }
        }
        .onChange(of: draft) { _, mapping in
            // A newly chosen shortcut or reference stays local until configured,
            // so leaving the page midway cannot invalidate the saved library.
            if mapping.isComplete { value = mapping }
        }
        .onChange(of: value) { _, mapping in draft = mapping }
    }

    private func actionTitle(_ action: RemoteAction) -> String {
        switch action {
        case .recordedShortcut: "自定义快捷键"
        case .phrase: "输入常用语"
        default: action.label
        }
    }
}
