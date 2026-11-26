import AppKit
import SwiftUI

@MainActor
struct MappingPage: View {
    @Environment(\.appColorMode) private var colorMode
    @ObservedObject var model: DashboardModel
    let editing: ControllerInput?
    let onRenameProfile: () -> Void
    let onEdit: (ControllerInput, Gesture) -> Void
    var body: some View {
        VStack(spacing: SettingsStyle.Spacing.controls) {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                Picker("编辑方案", selection: Binding(get: { model.selectedProfileID }, set: model.selectProfile)) {
                    ForEach(model.configuration.profiles) { Text($0.name).tag($0.id) }
                }
                .font(SettingsStyle.Typography.body)
                .frame(minWidth: 195, idealWidth: 270, maxWidth: 300)
                Button(action: onRenameProfile) { Image(systemName: "pencil") }
                    .accessibilityLabel("重命名当前按键方案")
                    .help("重命名当前按键方案")
                Divider().frame(height: 20)
                activeProfileStatus
                    .layoutPriority(1)
                Spacer(minLength: 0)
                bindingStatus
                Button("管理绑定") { model.page = .harnesses }
                    .fixedSize()
            }
            .buttonStyle(SettingsActionButtonStyle())
            .padding(.horizontal, SettingsStyle.controlPadding)
            .padding(.vertical, SettingsStyle.Spacing.inline)
            .background(SettingsStyle.panelBackground, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsStyle.panelRadius)
                    .strokeBorder(SettingsStyle.workspaceDivider)
                    .allowsHitTesting(false)
            }
            ControllerMappingDiagram(model: model, editing: editing, onEdit: onEdit)
        }
    }

    private var activeProfileStatus: some View {
        let profile = model.activeProfile
        let isEditingActiveProfile = profile.id == model.selectedProfileID
        let title = isEditingActiveProfile ? "当前生效" : "生效方案"
        return Group {
            if model.enabled {
                HStack(spacing: 6) {
                    Label(title, systemImage: isEditingActiveProfile ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(colorMode.palette.selectionTint)
                        .fixedSize()
                    if !isEditingActiveProfile {
                        Text(profile.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .help("当前生效的方案是「\(profile.name)」")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("生效方案")
                .accessibilityValue(profile.name)
            } else {
                Label("映射已暂停", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(SettingsStyle.Typography.body)
    }

    private var bindingStatus: some View {
        let bindings = model.configuration.harnesses.filter { $0.profileID == model.selectedProfileID }
        let description = bindings.isEmpty ? "编辑方案未绑定应用" : "编辑方案已绑定 \(bindings.map(\.name).joined(separator: "、"))"
        return HStack(spacing: SettingsStyle.Spacing.inline) {
            if bindings.isEmpty {
                bindingIcon(nil)
                Text("未绑定应用").foregroundStyle(.secondary).fixedSize()
            } else {
                ViewThatFits(in: .horizontal) {
                    bindingIcons(bindings).fixedSize(horizontal: true, vertical: false)
                    ScrollView(.horizontal) { bindingIcons(bindings) }.frame(height: 26)
                }
                Text("已绑定").foregroundStyle(.secondary).fixedSize()
            }
        }
        .font(SettingsStyle.Typography.body)
        .frame(maxWidth: 166, alignment: .trailing)
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    private func bindingIcons(_ bindings: [HarnessBinding]) -> some View {
        HStack(spacing: -4) {
            ForEach(bindings) { bindingIcon($0) }
        }
    }

    private func bindingIcon(_ binding: HarnessBinding?) -> some View {
        Group {
            if let url = binding?.installedApplicationURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(2)
            } else {
                HarnessIcon(size: 14).foregroundStyle(binding == nil ? Color.secondary : colorMode.palette.selectionTint)
            }
        }
        .frame(width: 20, height: 20)
        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.12)) }
        .opacity(binding?.enabled == false ? 0.45 : 1)
    }
}

@MainActor
struct ControllerMappingDiagram: View {
    @Environment(\.appColorMode) private var colorMode
    @ObservedObject var model: DashboardModel
    var editing: ControllerInput? = nil
    var onEdit: ((ControllerInput, Gesture) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredCard: ControllerInput?
    @State private var hoveredArtwork: ControllerInput?
    @FocusState private var focusedTrigger: TriggerFocus?

    private struct TriggerFocus: Hashable {
        let input: ControllerInput
        let gesture: Gesture
    }

    private var previewInput: ControllerInput? { editing ?? hoveredArtwork ?? hoveredCard ?? focusedTrigger?.input }
    private var emphasized: Set<ControllerInput> { model.pressed.union(previewInput.map { [$0] } ?? []) }
    private var side: JoyConSide { model.controllerProfile.side }
    private var columns: [[ControllerInput]] {
        let inputs: [[ControllerInput]] = side == .left
            ? [[.l, .leftStick, .up, .left, .down], [.zl, .minus, .leftSL, .right, .leftSR, .capture]]
            : [[.zr, .plus, .rightSR, .y, .rightSL, .c], [.r, .x, .a, .b, .rightStick, .home]]
        return inputs.map { $0.filter(model.controllerInputs.contains) }
    }

    var body: some View {
        VStack(spacing: SettingsStyle.Spacing.controls) {
            GeometryReader { proxy in
                let columns = columns
                let centerWidth = min(240, max(180, proxy.size.width * 0.22))
                let rowSpacing: CGFloat = 6
                let rowCount = CGFloat(columns.map(\.count).max() ?? 1)
                let rowHeight = (proxy.size.height - rowSpacing * (rowCount - 1)) / rowCount
                let columnWidth = (proxy.size.width - centerWidth) / 2
                HStack(alignment: .top, spacing: 0) {
                    cardColumn(columns[0], height: rowHeight, spacing: rowSpacing).frame(width: columnWidth)
                    JoyConArtwork(side: side, pressed: emphasized,
                                  onSelect: onEdit.map { edit in { edit($0, .single) } }, onHover: { hoveredArtwork = $0 },
                                  generation: model.controllerProfile.generation, showsStickDirections: true)
                        .frame(width: centerWidth, height: proxy.size.height)
                        .accessibilityHidden(onEdit == nil)
                    cardColumn(columns[1], height: rowHeight, spacing: rowSpacing).frame(width: columnWidth)
                }
                .overlayPreferenceValue(JoyConControlBounds.self) { anchors in
                    GeometryReader { geometry in
                        Canvas { context, _ in
                            for (column, inputs) in columns.enumerated() {
                                for (row, input) in inputs.enumerated() {
                                    guard let anchor = anchors[input] else { continue }
                                    let target = geometry[anchor]
                                    let fromLeft = column == 0
                                    let direction: CGFloat = fromLeft ? 1 : -1
                                    let start = CGPoint(x: fromLeft ? columnWidth + 3 : columnWidth + centerWidth - 3,
                                                        y: CGFloat(row) * (rowHeight + rowSpacing) + rowHeight / 2)
                                    let offsets = connectorOffsets(for: input)
                                    let end = CGPoint(x: (fromLeft ? target.minX : target.maxX) + direction * offsets.inset,
                                                      y: target.midY + offsets.tipY)
                                    let faceEdge = geometry.size.width / 2 - direction * JoyConArtwork.faceWidth / 2
                                    let edge = fromLeft ? min(faceEdge, end.x) : max(faceEdge, end.x)
                                    let entry = CGPoint(x: edge, y: target.midY + offsets.entryY)
                                    let lane = edge - direction * 12
                                    let color = emphasized.contains(input) ? colorMode.palette.selectionTint : .primary.opacity(colorScheme == .dark ? 0.26 : 0.17)
                                    let width: CGFloat = model.pressed.contains(input) ? 2 : emphasized.contains(input) ? 1.5 : 1
                                    var guide = Path()
                                    guide.move(to: start)
                                    guide.addCurve(to: entry,
                                                   control1: CGPoint(x: lane, y: start.y), control2: CGPoint(x: lane, y: entry.y))
                                    context.stroke(guide, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                                    var leader = Path()
                                    leader.move(to: entry)
                                    if entry.y == end.y {
                                        leader.addLine(to: end)
                                    } else {
                                        leader.addCurve(to: end,
                                                        control1: CGPoint(x: end.x - direction * 14, y: entry.y),
                                                        control2: CGPoint(x: end.x - direction * 7, y: end.y))
                                    }
                                    leader.move(to: CGPoint(x: end.x - direction * 4, y: end.y - 2.5))
                                    leader.addLine(to: end)
                                    leader.addLine(to: CGPoint(x: end.x - direction * 4, y: end.y + 2.5))
                                    context.stroke(leader, with: .color(emphasized.contains(input) ? colorMode.palette.selectionTint : .white.opacity(0.46)),
                                                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    Label("摇杆方向", systemImage: "l.joystick")
                        .font(SettingsStyle.Typography.body.weight(.semibold))
                    Text(stickModeLabel)
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    ForEach(ControllerInput.stickDirections(for: side)) { input in
                        mappingCard(input, height: onEdit == nil ? 62 : 56)
                    }
                }
            }
        }
        .onChange(of: editing) { _, _ in
            hoveredCard = nil
            hoveredArtwork = nil
        }
        .onChange(of: model.controllerProfile.id) { _, _ in
            hoveredCard = nil
            hoveredArtwork = nil
        }
    }

    private var stickModeLabel: String {
        let mode = model.currentStickMode(for: side)
        return onEdit == nil && mode == .pointer ? "鼠标模式 · 方向绑定暂停" : mode.label
    }

    private func connectorOffsets(for input: ControllerInput) -> (inset: CGFloat, tipY: CGFloat, entryY: CGFloat) {
        let isSecondGeneration = model.controllerProfile.generation == .second
        switch input {
        case .minus, .plus: return (4, 0, 0)
        case .y: return (5, 7, 36) // Pass below SR.
        case .leftStick, .rightStick: return (7, 15, 15) // Pass below the horizontal stick direction.
        case .capture: return (3, 3, isSecondGeneration ? 12 : 3) // Pass below the lower rail button.
        default: return (3, 0, 0)
        }
    }

    private func cardColumn(_ inputs: [ControllerInput], height: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(inputs) { mappingCard($0, height: height) }
        }
    }

    private func mappingCard(_ input: ControllerInput, height: CGFloat) -> some View {
        let active = emphasized.contains(input)
        let pressed = model.pressed.contains(input)
        let shape = RoundedRectangle(cornerRadius: SettingsStyle.controlRadius)
        return Group {
            if model.voiceInput == input {
                voiceCard(input, height: height)
            } else {
                gestureCard(input, pressed: pressed)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: height)
            }
        }
        .background(active ? colorMode.palette.selectionTint.opacity(pressed ? 0.17 : 0.09) : SettingsStyle.subtle, in: shape)
        .overlay {
            shape.strokeBorder(active ? colorMode.palette.selectionTint.opacity(pressed ? 0.82 : 0.5) : Color.primary.opacity(0.07))
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            if hovering { hoveredCard = input }
            else if hoveredCard == input { hoveredCard = nil }
        }
    }

    private func voiceCard(_ input: ControllerInput, height: CGFloat) -> some View {
        let shortcut = model.voiceButton.shortcut
        let summary = "\(shortcut.mode.title) · \(shortcut.label)"
        let label = VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(input.label, systemImage: "mic").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("全局").foregroundStyle(colorMode.palette.selectionTint)
            }
            Text(summary).foregroundStyle(.secondary).lineLimit(1)
        }
        .font(SettingsStyle.Typography.caption)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .contentShape(Rectangle())

        return Group {
            if let onEdit {
                Button { onEdit(input, .single) } label: { label }
                    .buttonStyle(.plain)
                    .focused($focusedTrigger, equals: .init(input: input, gesture: .single))
                    .help("编辑语音模式和快捷键")
            } else {
                label.help(summary).accessibilityElement(children: .ignore)
            }
        }
        .accessibilityLabel(input.label)
        .accessibilityValue(summary)
    }

    private func gestureCard(_ input: ControllerInput, pressed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Label(input.label, systemImage: input.symbol).fontWeight(.semibold)
                Spacer(minLength: 0)
                if model.globalButton(for: input) != nil {
                    Text("全局")
                        .foregroundStyle(colorMode.palette.selectionTint)
                        .accessibilityLabel("全局按键")
                }
                if pressed { Circle().fill(.green).frame(width: 6, height: 6) }
            }
            .font(SettingsStyle.Typography.caption)
            HStack(spacing: 0) {
                ForEach(Gesture.allCases) { trigger in triggerButton(input, trigger: trigger) }
            }
        }
    }

    private func triggerButton(_ input: ControllerInput, trigger: Gesture) -> some View {
        let mapping = onEdit == nil
            ? model.activeMapping(for: input, gesture: trigger)
            : model.mappingForEditing(input, gesture: trigger)
        let configured = mapping.action != .disabled
        let title = model.mappingSummary(mapping)
        let focus = TriggerFocus(input: input, gesture: trigger)
        let label = VStack(alignment: .leading, spacing: 0) {
            Text(trigger.label).font(.system(size: 10))
                .foregroundStyle(SettingsStyle.mappingTriggerLabel(in: colorScheme))
                .lineLimit(1)
            Text(configured ? title : "– 未设置").font(.system(size: 11, weight: configured ? .semibold : .regular))
                .foregroundStyle(configured ? .primary : SettingsStyle.mappingTriggerLabel(in: colorScheme))
                .lineLimit(onEdit == nil ? 2 : 1)
                .fixedSize(horizontal: false, vertical: onEdit == nil)
        }
        .padding(.leading, 8).padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())

        return Group {
            if let onEdit {
                Button { onEdit(input, trigger) } label: { label }
                    .buttonStyle(MappingTriggerButtonStyle(isConfigured: configured, isFocused: focusedTrigger == focus))
                    .focused($focusedTrigger, equals: focus)
            } else {
                label.background { MappingTriggerBackground(isConfigured: configured) }
                    .accessibilityElement(children: .ignore)
            }
        }
        .overlay(alignment: .leading) {
            if trigger != .single {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1)
                    .padding(.vertical, 3).allowsHitTesting(false)
            }
        }
        .help("\(input.label) · \(trigger.label)：\(title)")
        .accessibilityLabel("\(input.label)\(trigger.label)")
        .accessibilityValue(title)
    }
}

private struct MappingTriggerButtonStyle: ButtonStyle {
    let isConfigured: Bool
    let isFocused: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        TriggerButton(configuration: configuration, isConfigured: isConfigured, isFocused: isFocused)
    }

    private struct TriggerButton: View {
        let configuration: ButtonStyleConfiguration
        let isConfigured: Bool
        let isFocused: Bool
        @State private var hovered = false

        var body: some View {
            let interaction = configuration.isPressed ? 0.06 : hovered ? 0.03 : 0
            configuration.label.background {
                MappingTriggerBackground(isConfigured: isConfigured, isFocused: isFocused, interaction: interaction)
            }
            .onHover { hovered = $0 }
        }
    }
}

private struct MappingTriggerBackground: View {
    @Environment(\.appColorMode) private var colorMode
    @Environment(\.colorScheme) private var colorScheme
    let isConfigured: Bool
    var isFocused = false
    var interaction = 0.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        let base = isConfigured ? (colorScheme == .dark ? 0.10 : 0.08) : 0
        shape.fill(Color.primary.opacity(base + interaction))
            .overlay { shape.strokeBorder(isFocused ? colorMode.palette.selectionTint : .clear) }
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }
}

struct JoyConControlBounds: PreferenceKey {
    static let defaultValue: [ControllerInput: Anchor<CGRect>] = [:]

    static func reduce(value: inout [ControllerInput: Anchor<CGRect>], nextValue: () -> [ControllerInput: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
