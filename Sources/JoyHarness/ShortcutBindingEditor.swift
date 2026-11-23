import AppKit
import SwiftUI

struct ShortcutBindingEditor: View {
    @Binding var shortcut: RecordedShortcut?
    @Binding var keyboardShortcut: Binding<RecordedShortcut?>?
    var onRecordingChanged: (Bool) -> Void = { _ in }
    @State private var capturing = false
    @State private var progress = ShortcutRecordingSession.Progress.waiting

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
            HStack {
                Text(shortcut?.label ?? "尚未设置快捷键")
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .help(shortcut?.label ?? "")
                Spacer(minLength: SettingsStyle.Spacing.inline)
                Button("键盘选键") {
                    capturing = false
                    keyboardShortcut = $shortcut
                }
                .fixedSize()
                Button(capturing ? "取消录制" : "录制快捷键") {
                    progress = .waiting
                    capturing.toggle()
                }
                .fixedSize()
            }
            if capturing {
                Text(recordingHint)
                    .font(SettingsStyle.Typography.caption)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                ShortcutCapture(onCapture: {
                    shortcut = $0
                    capturing = false
                }, onCancel: { capturing = false }, onProgress: { progress = $0 })
                    .frame(height: 1)
                    .onAppear { onRecordingChanged(true) }
                    .onDisappear { onRecordingChanged(false) }
            }
        }
        .onDisappear { capturing = false }
    }

    private var recordingHint: String {
        switch progress {
        case .waiting: "请按下并松开快捷键。离开窗口将取消录制。"
        case .waitingForRelease(let label): "松开按键以录入「\(label)」。"
        case .tooManyKeys: "每次可录制一个主键。请松开所有按键后重试。"
        }
    }
}

@MainActor
struct ShortcutCapture: NSViewRepresentable {
    var onCapture: (RecordedShortcut) -> Void
    var onCancel: () -> Void
    var onProgress: (ShortcutRecordingSession.Progress) -> Void = { _ in }

    func makeNSView(context: Context) -> CaptureField {
        let view = CaptureField()
        updateCallbacks(view)
        return view
    }

    func updateNSView(_ view: CaptureField, context: Context) { updateCallbacks(view) }

    private func updateCallbacks(_ view: CaptureField) {
        // Deliver outside the AppKit event / view update stack. A removed recording
        // field must not overwrite a newer recording's state with a late result.
        view.session.onCapture = { [weak view] shortcut in
            view?.completeRecording { onCapture(shortcut) }
        }
        view.onCancel = { [weak view] in
            view?.deliverIfAttached { onCancel() }
        }
        view.session.onProgress = { [weak view] progress in
            view?.deliverIfAttached { onProgress(progress) }
        }
    }

    static func dismantleNSView(_ view: CaptureField, coordinator: ()) { view.stopRecording() }

    @MainActor
    final class CaptureField: NSView {
        let session: ShortcutRecordingSession
        var onCancel: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        private var completed = false
        private var generation = 0
        override var acceptsFirstResponder: Bool { true }

        init(session: ShortcutRecordingSession) {
            self.session = session
            super.init(frame: .zero)
        }

        override init(frame: NSRect) {
            session = ShortcutRecordingSession()
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopRecording()
            guard let window else { return }
            for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject),
                                   (NSWindow.willCloseNotification, window as AnyObject),
                                   (NSApplication.didResignActiveNotification, NSApp as AnyObject)] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelRecording() }
                })
            }
            let generation = generation
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, self.generation == generation else { return }
                guard window.isKeyWindow, NSApp.isActive, window.makeFirstResponder(self) else {
                    self.cancelRecording()
                    return
                }
                self.session.start()
                self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                    let consumed = MainActor.assumeIsolated {
                        guard let self, let window = self.window, window.isKeyWindow,
                              event.window == nil || event.window === window else { return false }
                        return self.receive(event)
                    }
                    return consumed ? nil : event
                }
            }
        }

        override func keyDown(with event: NSEvent) { receive(event) }
        override func keyUp(with event: NSEvent) { receive(event) }
        override func flagsChanged(with event: NSEvent) { receive(event) }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, session.isRecording, event.type == .keyDown else { return false }
            return receive(event)
        }

        @discardableResult
        private func receive(_ event: NSEvent) -> Bool {
            guard window?.firstResponder === self, let cgEvent = event.cgEvent else { return false }
            return session.handle(cgEvent.type, event: cgEvent)
        }

        override func resignFirstResponder() -> Bool {
            cancelRecording()
            return super.resignFirstResponder()
        }

        func stopRecording() {
            generation += 1
            session.stop()
            completed = false
            removeKeyMonitor()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }

        private func removeKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        func deliverIfAttached(_ action: @escaping () -> Void) {
            let generation = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.generation == generation else { return }
                action()
            }
        }

        func completeRecording(_ action: @escaping () -> Void) {
            completed = true
            removeKeyMonitor()
            deliverIfAttached(action)
        }

        private func cancelRecording() {
            guard !completed else { return }
            stopRecording()
            onCancel?()
        }

        deinit {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
