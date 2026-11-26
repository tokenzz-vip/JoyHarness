import AppKit
import Combine
import SwiftUI

@MainActor
final class PhrasePickerModel: ObservableObject {
    private static let instructions = "单击输入内容 1 · 双击输入内容 2"
    private static let closeInputs: Set<ControllerInput> = [.b, .home, .minus]
    @Published private(set) var isPresented = false
    @Published private(set) var phrases: [ControllerInput: SavedPhrase] = [:]
    @Published private(set) var message = PhrasePickerModel.instructions
    @Published private(set) var selectedInput: ControllerInput?
    @Published var colorMode = AppColorMode.iris
    var onOutput: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private final class Session {
        let phrase: SavedPhrase
        var second = false
        var work: DispatchWorkItem?
        init(_ phrase: SavedPhrase) { self.phrase = phrase }
    }
    private let schedule: CommandQueue.Scheduler
    private var controllerInputs: Set<ControllerInput> = []
    private var stickDirection: ControllerInput?
    private var sessions: [ControllerInput: Session] = [:]

    init(schedule: @escaping CommandQueue.Scheduler = CommandQueue.mainQueue) { self.schedule = schedule }

    func present(phrases: [SavedPhrase], assignments: PhraseAssignments) {
        dismiss()
        let byID = Dictionary(phrases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.phrases = Dictionary(uniqueKeysWithValues: PhraseAssignments.inputs.compactMap { input in
            assignments[input].flatMap { byID[$0] }.map { (input, $0) }
        })
        message = self.phrases.isEmpty ? "先在常用语页分配常用语" : Self.instructions
        isPresented = true
    }

    func dismiss() {
        guard isPresented else { return }
        for session in sessions.values { session.work?.cancel() }
        sessions.removeAll()
        controllerInputs.removeAll()
        stickDirection = nil
        selectedInput = nil
        isPresented = false
        onDismiss?()
    }

    func receive(_ snapshot: JoyConSnapshot, center: StickCenter?, deadzone: Double, baseline: Bool = false) {
        guard isPresented else { return }
        let stick = snapshot.stick.normalized(center: center, deadzone: deadzone)
        let strength = max(abs(stick.x), abs(stick.y))
        if strength <= 0.2 {
            stickDirection = nil
        } else if strength > 0.3 && stickDirection == nil {
            // Latch one direction until the stick returns to center, including at diagonals.
            if abs(stick.x) > abs(stick.y) {
                stickDirection = stick.x > 0 ? .right : .left
            } else {
                stickDirection = stick.y > 0 ? .up : .down
            }
        }
        var nextInputs = snapshot.buttons
        if nextInputs.contains(.leftStick) || nextInputs.contains(.rightStick) { nextInputs.insert(.a) }
        if let stickDirection { nextInputs.insert(stickDirection) }

        let released = controllerInputs.subtracting(nextInputs)
        let pressed = nextInputs.subtracting(controllerInputs)
        controllerInputs = nextInputs
        guard !baseline else { return }
        if !pressed.isDisjoint(with: Self.closeInputs) {
            dismiss()
            return
        }
        for input in PhraseAssignments.inputs where released.contains(input) {
            guard isPresented else { return }
            endSelection(input)
        }
        for input in PhraseAssignments.inputs where pressed.contains(input) {
            guard isPresented else { return }
            beginSelection(input)
        }
    }

    func click(_ input: ControllerInput) {
        guard isPresented, !controllerInputs.contains(input) else { return }
        beginSelection(input)
        endSelection(input)
    }

    private func beginSelection(_ input: ControllerInput) {
        guard let phrase = phrases[input] else { return }
        selectedInput = input
        message = Self.instructions
        if let session = sessions[input] {
            session.work?.cancel()
            session.second = true
        } else {
            sessions[input] = Session(phrase)
        }
    }

    private func endSelection(_ input: ControllerInput) {
        guard let session = sessions[input] else { return }
        if session.second {
            output(session.phrase, language: .english)
        } else {
            session.work = schedule(GestureController.doubleTapWindow) { [weak self, weak session] in
                guard let self, let session, self.isPresented, self.sessions[input] === session else { return }
                self.output(session.phrase, language: .chinese)
            }
        }
    }

    private func output(_ phrase: SavedPhrase, language: PhraseLanguage) {
        guard isPresented else { return }
        let text = language == .english ? phrase.englishText : phrase.text
        guard !text.isEmpty else {
            for session in sessions.values { session.work?.cancel() }
            sessions.removeAll()
            selectedInput = nil
            message = language == .english ? "这条常用语的内容 2 为空" : "这条常用语的内容 1 为空"
            return
        }
        dismiss()
        onOutput?(text)
    }
}

@MainActor
final class PhrasePickerController {
    let model = PhrasePickerModel()
    private var panel: PhrasePickerPanel?
    var renderView: NSView? { panel?.contentView }

    init(onDismiss: @escaping () -> Void, onOutput: @escaping (String) -> Void) {
        model.onOutput = onOutput
        model.onDismiss = { [weak self] in
            self?.panel?.orderOut(nil)
            onDismiss()
        }
    }

    func show(phrases: [SavedPhrase], assignments: PhraseAssignments, colorMode: AppColorMode) {
        model.colorMode = colorMode
        model.present(phrases: phrases, assignments: assignments)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = PhrasePickerView.panelSize
        if panel == nil {
            let panel = PhrasePickerPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.onCancel = { [weak self] in self?.model.dismiss() }
            panel.contentView = NSHostingView(rootView: PhrasePickerView(model: model)); self.panel = panel
        }
        panel?.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct PhrasePickerView: View {
    static let panelSize = NSSize(width: 296, height: 360)

    @ObservedObject var model: PhrasePickerModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("常用语").font(.system(size: 14, weight: .medium))
                Spacer()
                Button { model.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭常用语（B、HOME、− 或 Esc）")
                .accessibilityLabel("关闭常用语")
            }
            .frame(height: 24)
            PhrasePadView(title: { model.phrases[$0]?.displayTitle ?? "未分配" },
                          isAssigned: { model.phrases[$0] != nil }, showsAssignmentMarks: false,
                          diameter: 244, selectedInput: model.selectedInput, onSelect: model.click)
                .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                Text(model.message)
                Text("拨动摇杆选方向 · 按下摇杆等同 A")
                Text("B / HOME / − / Esc 关闭")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(height: 52)
        }
        .padding(12)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08)) }
        .environment(\.appColorMode, model.colorMode)
        .tint(model.colorMode.palette.selectionTint)
    }
}

@MainActor
private final class PhrasePickerPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == VirtualKey.escape { onCancel?() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func resignKey() { super.resignKey(); onCancel?() }
}

@MainActor
struct PhrasePadView: View {
    let title: (ControllerInput) -> String
    let isAssigned: (ControllerInput) -> Bool
    let showsAssignmentMarks: Bool
    let diameter: CGFloat
    let onSelect: (ControllerInput) -> Void
    let selectedInput: ControllerInput?
    @State private var hoveredInput: ControllerInput?
    @State private var pressedInput: ControllerInput?
    @FocusState private var focusedInput: ControllerInput?
    private var scale: CGFloat { diameter / 212 }

    init(title: @escaping (ControllerInput) -> String, isAssigned: @escaping (ControllerInput) -> Bool = { _ in false }, showsAssignmentMarks: Bool = true, diameter: CGFloat = 212, selectedInput: ControllerInput? = nil, onSelect: @escaping (ControllerInput) -> Void) {
        self.title = title; self.isAssigned = isAssigned; self.showsAssignmentMarks = showsAssignmentMarks; self.diameter = diameter; self.selectedInput = selectedInput; self.onSelect = onSelect
    }
    var body: some View {
        ZStack {
            directionButton(.up, angle: -90); directionButton(.left, angle: 180); directionButton(.right, angle: 0); directionButton(.down, angle: 90)
            Button { onSelect(.a) } label: { keyLabel(.a).frame(width: 66 * scale, height: 66 * scale) }
                .buttonStyle(PhrasePadKeyStyle(shape: Circle(), hovered: hoveredInput == .a, pressed: pressedInput == .a, focused: focusedInput == .a || selectedInput == .a)).focused($focusedInput, equals: .a)
                .help("\(ControllerInput.a.label)：\(title(.a))")
                .accessibilityLabel("\(ControllerInput.a.label)：\(title(.a))")
        }.frame(width: diameter, height: diameter).overlay { PhrasePadInputSurface(onSelect: onSelect, onHover: { hoveredInput = $0 }, onPress: { pressedInput = $0 }) }
    }
    private func directionButton(_ input: ControllerInput, angle: Double) -> some View {
        Button { onSelect(input) } label: { ZStack { keyLabel(input).frame(width: 66 * scale, height: 66 * scale).position(x: PhrasePadLayout.position(for: input).x * scale, y: PhrasePadLayout.position(for: input).y * scale) }.frame(width: diameter, height: diameter) }
            .buttonStyle(PhrasePadKeyStyle(shape: PhrasePadSector(angle: angle), hovered: hoveredInput == input, pressed: pressedInput == input, focused: focusedInput == input || selectedInput == input)).focused($focusedInput, equals: input)
            .help("\(input.label)：\(title(input))")
            .accessibilityLabel("\(input.label)：\(title(input))")
    }
    private func keyLabel(_ input: ControllerInput) -> some View {
        VStack(spacing: 6 * scale) {
            if input == .a { Text("A").font(.system(size: 15 * scale, weight: .semibold)) } else { Image(systemName: input.symbol).font(.system(size: 15 * scale, weight: .medium)) }
            HStack(spacing: 3 * scale) { Text(title(input)).font(.system(size: 11 * scale, weight: .medium)).lineLimit(1).truncationMode(.middle); if showsAssignmentMarks && isAssigned(input) { Image(systemName: "checkmark").font(.system(size: 7 * scale, weight: .semibold)).foregroundStyle(.secondary) } }.foregroundStyle(isAssigned(input) ? .primary : .secondary)
        }.accessibilityHidden(true)
    }
}

enum PhrasePadLayout {
    static func position(for input: ControllerInput) -> CGPoint { switch input { case .up: CGPoint(x: 106, y: 38); case .down: CGPoint(x: 106, y: 174); case .left: CGPoint(x: 38, y: 106); case .right: CGPoint(x: 174, y: 106); default: CGPoint(x: 106, y: 106) } }
    static func anchor(for input: ControllerInput) -> UnitPoint { let point = position(for: input); return UnitPoint(x: point.x / 212, y: point.y / 212) }
    static func input(at point: CGPoint, in bounds: CGRect) -> ControllerInput? {
        guard bounds.contains(point) else { return nil }
        let centerSize = min(bounds.width, bounds.height) * 66 / 212
        if Path(ellipseIn: CGRect(x: bounds.midX - centerSize / 2, y: bounds.midY - centerSize / 2, width: centerSize, height: centerSize)).contains(point) { return .a }
        for (input, angle): (ControllerInput, Double) in [(.up, -90), (.left, 180), (.right, 0), (.down, 90)] where PhrasePadSector(angle: angle).path(in: bounds).contains(point) { return input }
        return nil
    }
}

private struct PhrasePadSector: Shape {
    let angle: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2 - 1
        let start = Angle.degrees(angle - 43.5), end = Angle.degrees(angle + 43.5); var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false); path.addArc(center: center, radius: radius * 0.36, startAngle: end, endAngle: start, clockwise: true); path.closeSubpath(); return path
    }
}

private struct PhrasePadKeyStyle<S: Shape>: ButtonStyle {
    @Environment(\.appColorMode) private var colorMode
    @Environment(\.colorScheme) private var colorScheme
    let shape: S; let hovered: Bool; let pressed: Bool; let focused: Bool
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label.foregroundStyle(.primary).background { shape.fill(SettingsStyle.phrasePadKeyBackground(in: colorScheme)).overlay { shape.fill(Color.primary.opacity(configuration.isPressed || pressed ? 0.10 : hovered ? 0.05 : 0)) } }.overlay { shape.stroke(focused ? colorMode.palette.selectionTint : Color.primary.opacity(hovered ? 0.24 : 0.16), lineWidth: focused ? 2 : 1) }.contentShape(shape)
    }
}

