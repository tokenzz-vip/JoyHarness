import SwiftUI

@MainActor
struct PhrasesPage: View {
    @Environment(\.appColorMode) private var colorMode
    @ObservedObject var model: DashboardModel
    @State private var selectedPhraseID: UUID?
    @State private var assignmentInput: ControllerInput?

    init(model: DashboardModel) {
        self.model = model
        _selectedPhraseID = State(initialValue: model.orderedPhrases.first?.id)
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsStyle.Spacing.groups) {
            assignmentPanel.frame(width: 252)
            SettingsPanel(contentPadding: EdgeInsets()) {
                phraseListPanel
            }
            .frame(width: 232)
            phraseEditorPanel.frame(maxWidth: .infinity)
        }
        .padding(SettingsStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.configuration.phrases.map(\.id)) { _, _ in ensureSelection() }
    }

    private var assignmentPanel: some View {
        SettingsPanel("按键分配", symbol: "gamecontroller") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
                    Text("把常用语放到手柄的五个输入位置。")
                        .font(SettingsStyle.Typography.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: SettingsStyle.Spacing.inline) {
                        Image(systemName: "circle.grid.2x2.fill")
                        Text("\(boundPhraseCount) / \(PhraseAssignments.inputs.count) 个位置已绑定")
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .font(SettingsStyle.Typography.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(SettingsStyle.compactControlPadding)
                    .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                }
                Spacer(minLength: 24)
                PhrasePadView(title: assignmentTitle, isAssigned: { input in
                    model.configuration.phraseAssignments[input] != nil
                }, selectedInput: assignmentInput) { input in
                    assignmentInput = input
                }
                .popover(isPresented: Binding(get: { assignmentInput != nil }, set: { if !$0 { assignmentInput = nil } }),
                         attachmentAnchor: .point(PhrasePadLayout.anchor(for: assignmentInput ?? .up)),
                         arrowEdge: .trailing) {
                    if let input = assignmentInput {
                        PhraseAssignmentPicker(input: input, phrases: model.orderedPhrases,
                                               selection: model.configuration.phraseAssignments[input]) { id in
                            model.configuration.phraseAssignments[input] = id
                            assignmentInput = nil
                        }
                        .id(input)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
                    instructionRow("1.circle", title: "单击", detail: "输入内容 1")
                    instructionRow("2.circle", title: "双击", detail: "输入内容 2")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsStyle.controlPadding)
                .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsStyle.controlRadius)
                        .strokeBorder(Color.primary.opacity(0.10))
                }
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
                    Divider()
                    Text("如何唤出").font(SettingsStyle.Typography.body.weight(.medium))
                    Text("先在按键映射中绑定“唤出常用语”，再用手柄打开浮层。")
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 24)
                Button {
                    model.page = .mapping
                } label: {
                    Label("返回按键映射", systemImage: "arrow.left")
                }
                .buttonStyle(SettingsActionButtonStyle())
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var boundPhraseCount: Int {
        PhraseAssignments.inputs.filter { model.configuration.phraseAssignments[$0] != nil }.count
    }

    private func instructionRow(_ symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: SettingsStyle.Spacing.inline) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colorMode.palette.selectionTint)
                .frame(width: 18)
            Text(title).font(SettingsStyle.Typography.body.weight(.semibold))
            Text(detail).font(SettingsStyle.Typography.body.weight(.medium))
        }
        .foregroundStyle(.primary)
    }

    private func assignmentTitle(_ input: ControllerInput) -> String {
        guard let id = model.configuration.phraseAssignments[input] else { return "未分配" }
        return model.configuration.phrases.first(where: { $0.id == id })?.displayTitle ?? "已删除"
    }

    private var phraseListPanel: some View {
        VStack(spacing: 0) {
            SettingsLibraryHeader(title: "常用语库") {
                Button {
                    let phrase = SavedPhrase(title: "新常用语", text: "")
                    model.configuration.phrases.append(phrase)
                    selectedPhraseID = phrase.id
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(SettingsActionButtonStyle())
                .controlSize(.small)
                .disabled(model.configuration.phrases.count >= 500)
            }
            HStack(alignment: .firstTextBaseline, spacing: SettingsStyle.Spacing.inline) {
                Text("已绑定置顶，其余可拖动排序")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(model.configuration.phrases.count) 条")
                    .monospacedDigit()
                    .fixedSize()
            }
            .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
            .padding(.horizontal, SettingsStyle.Spacing.groups)
            .padding(.bottom, SettingsStyle.Spacing.inline)
            if !model.configuration.phrases.isEmpty {
                phraseReorderButtons
                    .padding(.horizontal, SettingsStyle.Spacing.groups)
                    .padding(.bottom, SettingsStyle.Spacing.controls)
            }
            Divider()
            if model.configuration.phrases.isEmpty {
                VStack(spacing: SettingsStyle.Spacing.inline) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("还没有常用语")
                        .font(SettingsStyle.Typography.body.weight(.medium))
                    Text("点击“新建”开始添加")
                        .font(SettingsStyle.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                Spacer(minLength: 0)
            } else {
                PhraseListView(model: model, selectedPhraseID: $selectedPhraseID)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .padding(SettingsStyle.Spacing.inline)
            }
        }
    }

    private var phraseReorderButtons: some View {
        let phrases = model.unboundPhrases
        let index = phrases.firstIndex { $0.id == selectedPhraseID }
        return HStack(spacing: SettingsStyle.Spacing.inline) {
            Button {
                if let index, index > 0 {
                    model.moveUnboundPhrases(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                }
            } label: {
                Label("上移", systemImage: "arrow.up")
            }
            .disabled(index.map { $0 == 0 } ?? true)
            .accessibilityLabel("上移所选常用语")
            Button {
                if let index, index + 1 < phrases.count {
                    model.moveUnboundPhrases(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                }
            } label: {
                Label("下移", systemImage: "arrow.down")
            }
            .disabled(index.map { $0 + 1 >= phrases.count } ?? true)
            .accessibilityLabel("下移所选常用语")
            Spacer(minLength: 0)
        }
        .buttonStyle(SettingsActionButtonStyle())
        .controlSize(.small)
    }

    @ViewBuilder private var phraseEditorPanel: some View {
        if let phrase = selectedPhraseBinding {
            SettingsPanel {
                HStack(alignment: .firstTextBaseline, spacing: SettingsStyle.Spacing.inline) {
                    Text(phrase.wrappedValue.displayTitle)
                        .font(SettingsStyle.Typography.dialogTitle)
                        .accessibilityAddTraits(.isHeader)
                        .lineLimit(1)
                        .help(phrase.wrappedValue.displayTitle)
                    Spacer(minLength: 0)
                    Text("修改后自动保存")
                        .font(SettingsStyle.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
                        contentEditor("内容 1", title: phrase.title, text: phrase.text,
                                       titlePlaceholder: "内容1标题", textPlaceholder: "内容1正文")
                        Divider()
                        contentEditor("内容 2", title: phrase.englishTitle, text: phrase.englishText,
                                       titlePlaceholder: "内容2标题", textPlaceholder: "内容2正文")
                    }
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                Divider()
                HStack {
                    Spacer()
                    Button("删除", role: .destructive) {
                        guard let id = selectedPhraseID else { return }
                        model.requestPhraseDeletion(id)
                    }.controlSize(.small)
                }
            }
            .id(selectedPhraseID)
        } else {
            SettingsPanel("常用语内容", symbol: "pencil") {
                Spacer(minLength: 0)
                SettingsEmpty(symbol: "text.bubble", title: "选择一条常用语", detail: "选择后可编辑内容1和内容2的标题及正文。")
                Spacer(minLength: 0)
            }
        }
    }

    private func contentEditor(_ heading: String, title: Binding<String>, text: Binding<String>,
                                titlePlaceholder: String, textPlaceholder: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
            HStack {
                Text(heading).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    model.copyToPasteboard(text.wrappedValue, confirmation: "常用语已复制")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(SettingsStyle.Typography.caption.weight(.medium))
                .disabled(text.wrappedValue.isEmpty)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("标题").font(SettingsStyle.Typography.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField(titlePlaceholder, text: title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(titlePlaceholder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("正文").font(SettingsStyle.Typography.caption.weight(.medium)).foregroundStyle(.secondary)
                TextEditor(text: text)
                    .font(.system(size: 13)).frame(height: 116).scrollContentBackground(.hidden)
                    .padding(7)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                    .overlay { RoundedRectangle(cornerRadius: SettingsStyle.controlRadius).strokeBorder(Color.primary.opacity(0.12)) }
                    .overlay(alignment: .topLeading) {
                        if text.wrappedValue.isEmpty {
                            Text(textPlaceholder).font(.system(size: 13)).foregroundStyle(.tertiary)
                                .padding(SettingsStyle.controlPadding).allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(textPlaceholder)
            }
        }
    }

    private var selectedPhraseBinding: Binding<SavedPhrase>? {
        guard let id = selectedPhraseID, model.configuration.phrases.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.configuration.phrases.first(where: { $0.id == id }) ?? SavedPhrase(id: id, title: "", text: "") },
            set: { updated in
                guard let index = model.configuration.phrases.firstIndex(where: { $0.id == id }) else { return }
                model.configuration.phrases[index] = updated
            }
        )
    }

    private func ensureSelection() {
        if let selectedPhraseID, model.configuration.phrases.contains(where: { $0.id == selectedPhraseID }) { return }
        selectedPhraseID = model.orderedPhrases.first?.id
    }
}

