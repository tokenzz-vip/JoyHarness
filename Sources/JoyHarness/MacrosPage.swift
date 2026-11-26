import SwiftUI

struct MacrosPage: View {
    private enum ScrollTarget: Hashable { case addStep }

    @ObservedObject var model: DashboardModel
    @State private var selectedMacroID: UUID?
    @State private var macroNameDraft: String
    @State private var query = ""
    @State private var selectedTagIDs: Set<String> = []
    @State private var showsTagManager = false
    @State private var deleting = false
    @State private var keyboardShortcut: Binding<RecordedShortcut?>?

    private var visibleMacros: [ActionMacro] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.savedMacros.filter { macro in
            (selectedTagIDs.isEmpty || !macro.tagIDs.isDisjoint(with: selectedTagIDs)) &&
                (term.isEmpty || macro.name.localizedStandardContains(term))
        }
    }

    init(model: DashboardModel) {
        self.model = model
        _selectedMacroID = State(initialValue: model.savedMacros.first?.id)
        _macroNameDraft = State(initialValue: model.savedMacros.first?.name ?? "")
    }

    var body: some View {
        SettingsWorkspace {
            macroList
        } detail: {
            Group {
                if let index = model.savedMacros.firstIndex(where: { $0.id == selectedMacroID }) {
                    editor(index).id(model.savedMacros[index].id)
                } else {
                    SettingsEmpty(symbol: "square.3.layers.3d", title: "选择一个组合动作", detail: "选择后可编辑执行步骤和手柄绑定。")
                }
            }
            .padding(SettingsStyle.pagePadding)
        }
        .modifier(ShortcutKeyboardOverlay(shortcut: $keyboardShortcut) { active in
            if active { model.beginEditing() } else { model.endEditing() }
        })
        .confirmationDialog("删除组合动作？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除组合动作", role: .destructive) {
                if let selectedMacroID { model.deleteMacro(selectedMacroID) }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("同时清除使用此组合动作的按键映射和步骤引用。") }
        .onChange(of: selectedMacroID) { _, id in
            macroNameDraft = model.savedMacros.first(where: { $0.id == id })?.name ?? ""
        }
        .onChange(of: model.savedMacros.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedMacroID }) {
                selectedMacroID = visibleMacros.first?.id
            }
        }
        .onChange(of: visibleMacros.map(\.id)) { _, ids in
            if !ids.contains(where: { $0 == selectedMacroID }) {
                selectedMacroID = ids.first
            }
        }
        .onChange(of: model.customMacroTags.map(\.id)) { _, _ in
            selectedTagIDs.formIntersection(model.macroTags.map(\.id))
        }
        .sheet(isPresented: $showsTagManager) {
            MacroTagManagementSheet(model: model)
        }
    }

    private var macroList: some View {
        let macros = visibleMacros
        let tags = model.macroTags
        return VStack(spacing: 0) {
            SettingsLibraryHeader(title: "组合动作") {
                Button("管理标签", systemImage: "tag") { showsTagManager = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(SettingsActionButtonStyle())
                    .help("管理标签")
                Button("新建组合动作", systemImage: "plus") { addMacro() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(!model.canAddMacro)
                    .help(model.canAddMacro ? "新建组合动作" : "自定义组合动作已达上限")
            }
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                SettingsSearchField(prompt: "搜索组合动作", query: $query)
                tagFilterPicker.accessibilityLabel("按标签筛选组合动作")
            }
            .padding(.horizontal, SettingsStyle.Spacing.groups)
            .padding(.bottom, SettingsStyle.Spacing.controls)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    // Build only visible rows so opening a large library stays responsive.
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.savedMacros.isEmpty {
                            SettingsEmpty(symbol: DashboardPage.macros.symbol, title: "还没有组合动作", detail: "把多个本机操作连成一次顺手的按键。")
                            Button { addMacro() } label: {
                                Text("创建第一个组合动作").frame(maxWidth: .infinity)
                            }.buttonStyle(SettingsActionButtonStyle(prominent: true))
                        }
                        if !model.savedMacros.isEmpty && macros.isEmpty {
                            SettingsEmpty(symbol: "magnifyingglass", title: "没有匹配的组合动作", detail: "试试其他名称或标签。")
                            Button("显示全部动作") {
                                query = ""
                                selectedTagIDs.removeAll()
                            }
                                .buttonStyle(.link)
                        }
                        ForEach(macros) { macro in
                            let summary = tags.filter { macro.tagIDs.contains($0.id) }.map(\.name).joined(separator: " · ")
                            Button { selectedMacroID = macro.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(macro.name).font(SettingsStyle.Typography.listTitle).lineLimit(1)
                                            .help(macro.name)
                                        Text(summary.isEmpty ? "\(macro.steps.count) 个步骤" : "\(macro.steps.count) 个步骤 · \(summary)")
                                            .font(SettingsStyle.Typography.caption)
                                            .foregroundStyle(Color.secondary)
                                            .lineLimit(1)
                                            .help(summary)
                                    }
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, SettingsStyle.controlPadding)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                            }
                            .buttonStyle(SettingsSidebarRowStyle(selected: selectedMacroID == macro.id))
                            .accessibilityAddTraits(selectedMacroID == macro.id ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsStyle.Spacing.inline)
                }
                .onChange(of: selectedMacroID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func addMacro() {
        if let id = model.addMacro(tagIDs: selectedTagIDs.isEmpty ? [MacroTag.general.id] : selectedTagIDs) {
            query = ""
            selectedMacroID = id
        }
    }

    private var tagFilterPicker: some View {
        MacroTagFilter(selection: $selectedTagIDs, tags: model.macroTags)
    }

    private func tagEditor(_ macro: ActionMacro) -> some View {
        HStack(spacing: SettingsStyle.Spacing.inline) {
            Text("标签").font(SettingsStyle.Typography.body.weight(.semibold))
            MacroTagFilter(selection: Binding(
                get: { model.savedMacros.first(where: { $0.id == macro.id })?.tagIDs ?? [] },
                set: { model.updateMacroTags($0, for: macro.id) }
            ), tags: model.macroTags, isAssignment: true)
        }
    }

    private func editor(_ index: Int) -> some View {
        let macro = model.savedMacros[index]
        let nameError = model.macroNameError(macroNameDraft, excluding: macro.id)
        let steps = Binding(
            get: { model.savedMacros.first(where: { $0.id == macro.id })?.steps ?? [] },
            set: { model.updateMacroSteps($0, for: macro.id) }
        )
        return SettingsPanel("编辑组合动作", symbol: "slider.horizontal.3") {
            HStack {
                TextField("组合动作名称", text: $macroNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveName(macro.id) }
                Button("保存名称") { saveName(macro.id) }
                    .disabled(nameError != nil || macroNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == macro.name)
            }
            if let nameError {
                Text(nameError).font(.caption).foregroundStyle(.red)
            }
            tagEditor(macro)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsStyle.Spacing.controls) {
                        if steps.wrappedValue.isEmpty {
                            Text("还没有步骤，点击下方“添加步骤”开始配置。")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                        }
                        ForEach(steps) { $step in
                            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                                HStack {
                                    Text("步骤 \((macro.steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1)")
                                        .font(SettingsStyle.Typography.body.weight(.semibold))
                                    Spacer()
                                    Button { steps.wrappedValue.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("移除步骤")
                                }
                                MacroActionEditor(value: $step.mapping, model: model, parentMacroID: macro.id,
                                                  keyboardShortcut: $keyboardShortcut)
                                HStack {
                                    Text("执行后等待").font(.caption).foregroundStyle(Color.secondary)
                                    Slider(value: $step.delay, in: 0...3, step: 0.1)
                                    Text(String(format: "%.1f 秒", step.delay)).font(.caption.monospacedDigit()).frame(width: 45)
                                }
                            }
                            .padding(SettingsStyle.controlPadding).background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.controlRadius))
                            .id(step.id)
                        }
                        Button { steps.wrappedValue.append(MacroStep()) } label: {
                            Label("添加步骤", systemImage: "plus")
                        }
                        .id(ScrollTarget.addStep)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: macro.steps.map(\.id)) { old, new in
                    if new.count > old.count { proxy.scrollTo(ScrollTarget.addStep, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Button("删除组合动作", role: .destructive) {
                    deleting = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(model.colorMode.palette.destructiveTint)
                Spacer()
                Button("绑定到手柄") { model.requestMacroBinding(macro.id) }
                    .buttonStyle(SettingsActionButtonStyle(prominent: true)).disabled(macro.steps.isEmpty)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func saveName(_ id: UUID) {
        if model.renameMacro(id, name: macroNameDraft) {
            macroNameDraft = model.savedMacros.first(where: { $0.id == id })?.name ?? ""
        }
    }
}
