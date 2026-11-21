import AppKit
import SwiftUI

@MainActor
struct MappingPage: View {
    @ObservedObject var model: DashboardModel
    let editing: ControllerInput?
    let onRenameProfile: () -> Void
    let onEdit: (ControllerInput, Gesture) -> Void
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
            SettingsPanel {
                HStack(spacing: SettingsStyle.Spacing.controls) {
                    Picker("按键方案", selection: Binding(get: { model.selectedProfileID }, set: model.selectProfile)) {
                        ForEach(model.configuration.profiles) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 360)
                    Button(action: onRenameProfile) { Image(systemName: "pencil") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("重命名当前按键方案")
                        .help("重命名当前按键方案")
                    bindingStatus
                    Spacer(minLength: 0)
                    Button("管理绑定") { model.page = .harnesses }
                }
            }
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
                                  onSelect: { onEdit($0, .single) }, onHover: { hoveredArtwork = $0 },
                                  generation: model.controllerProfile.generation, showsStickDirections: true)
                        .frame(width: centerWidth, height: proxy.size.height)
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
                                    let color = emphasized.contains(input) ? Color.accentColor : .primary.opacity(colorScheme == .dark ? 0.26 : 0.17)
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
                                    context.stroke(leader, with: .color(emphasized.contains(input) ? .accentColor : .white.opacity(0.46)),
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
                    Text(model.currentStickMode(for: side).label)
                        .font(SettingsStyle.Typography.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    ForEach(ControllerInput.stickDirections(for: side)) { input in
                        mappingCard(input, height: 56)
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

    private var bindingStatus: some View {
        let bindings = model.configuration.harnesses.filter { $0.profileID == model.selectedProfileID }
        let bindingDescription = bindings.isEmpty ? "未绑定 Harness" : "已绑定 \(bindings.map(\.name).joined(separator: "、"))"
        let description = model.activeProfile.id == model.selectedProfileID
            ? bindingDescription : "\(bindingDescription)。当前应用使用 \(model.activeProfile.name)"
        return HStack(spacing: SettingsStyle.Spacing.inline) {
            if bindings.isEmpty {
                bindingIcon(nil)
                Text("未绑定 Harness").foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    bindingIcons(bindings).fixedSize(horizontal: true, vertical: false)
                    ScrollView(.horizontal) { bindingIcons(bindings) }.frame(height: 26)
                }
                Text("已绑定").fontWeight(.medium).fixedSize()
            }
        }
        .font(SettingsStyle.Typography.body)
        .frame(width: 245, height: 35, alignment: .leading)
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
                HarnessIcon(size: 14).foregroundStyle(binding == nil ? Color.secondary : Color.accentColor)
            }
        }
        .frame(width: 20, height: 20)
        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.12)) }
        .opacity(binding?.enabled == false ? 0.45 : 1)
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
        .background(active ? Color.accentColor.opacity(pressed ? 0.17 : 0.09) : SettingsStyle.subtle, in: shape)
        .overlay {
            shape.strokeBorder(active ? Color.accentColor.opacity(pressed ? 0.82 : 0.5) : Color.primary.opacity(0.07))
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
        return Button { onEdit(input, .single) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(input.label, systemImage: "mic").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("全局").foregroundStyle(Color.accentColor)
                }
                Text(summary).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(SettingsStyle.Typography.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTrigger, equals: .init(input: input, gesture: .single))
        .accessibilityLabel(input.label)
        .accessibilityValue(summary)
        .help("编辑语音模式和快捷键")
    }

    private func gestureCard(_ input: ControllerInput, pressed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Label(input.label, systemImage: input.symbol).fontWeight(.semibold)
                Spacer(minLength: 0)
                if model.globalButton(for: input) != nil {
                    Text("全局")
                        .foregroundStyle(Color.accentColor)
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
        let mapping = model.mappingForEditing(input, gesture: trigger)
        let configured = mapping.action != .disabled
        let title = model.mappingSummary(mapping)
        let focus = TriggerFocus(input: input, gesture: trigger)
        return Button { onEdit(input, trigger) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(trigger.label).font(.system(size: 10))
                    .foregroundStyle(SettingsStyle.mappingTriggerLabel(in: colorScheme))
                Text(configured ? title : "– 未设置").font(.system(size: 11, weight: configured ? .semibold : .regular))
                    .foregroundStyle(configured ? .primary : SettingsStyle.mappingTriggerLabel(in: colorScheme))
            }
            .lineLimit(1)
            .padding(.leading, 8).padding(.trailing, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MappingTriggerButtonStyle(isConfigured: configured, isFocused: focusedTrigger == focus))
        .focused($focusedTrigger, equals: focus)
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
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 4)
            let base = isConfigured ? (colorScheme == .dark ? 0.10 : 0.08) : 0
            let interaction = configuration.isPressed ? 0.06 : hovered ? 0.03 : 0
            configuration.label.background {
                shape.fill(Color.primary.opacity(base + interaction))
                    .overlay { shape.strokeBorder(isFocused ? Color.accentColor : .clear) }
                    .padding(.horizontal, 2).allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
        }
    }
}

struct JoyConControlBounds: PreferenceKey {
    static let defaultValue: [ControllerInput: Anchor<CGRect>] = [:]

    static func reduce(value: inout [ControllerInput: Anchor<CGRect>], nextValue: () -> [ControllerInput: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}
