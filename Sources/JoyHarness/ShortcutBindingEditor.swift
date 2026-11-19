import AppKit
import SwiftUI

struct ShortcutBindingEditor: View {
    @Binding var shortcut: RecordedShortcut?
    @Binding var capturing: Bool

    init(shortcut: Binding<RecordedShortcut?>, capturing: Binding<Bool>) {
        _shortcut = shortcut
        _capturing = capturing
    }

    init(shortcut: Binding<RecordedShortcut>, capturing: Binding<Bool>) {
        _shortcut = Binding(get: { shortcut.wrappedValue }, set: { if let value = $0 { shortcut.wrappedValue = value } })
        _capturing = capturing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.inline) {
            HStack {
                Text(shortcut?.label ?? "尚未设置快捷键").font(.system(size: 13, design: .monospaced))
                Spacer()
                Button(capturing ? "取消录制" : "录制快捷键") {
                    capturing.toggle()
                }
            }
            if capturing {
                Text("请按下并松开快捷键；离开窗口将取消录制。")
                    .font(.caption).foregroundStyle(Color.accentColor).fixedSize(horizontal: false, vertical: true)
                ShortcutCapture(onCapture: {
                    shortcut = $0
                    capturing = false
                }, onCancel: { capturing = false }).frame(height: 1)
            }
        }
    }
}

@MainActor
struct ShortcutCapture: NSViewRepresentable {
    var onCapture: (RecordedShortcut) -> Void
    var onCancel: () -> Void

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
            view?.deliverIfAttached { onCapture(shortcut) }
        }
        view.onCancel = { [weak view] in
            view?.deliverIfAttached { onCancel() }
        }
    }

    static func dismantleNSView(_ view: CaptureField, coordinator: ()) { view.stopRecording() }

    @MainActor
    final class CaptureField: NSView {
        let session: ShortcutRecordingSession
        var onCancel: (() -> Void)?
        private var observers: [NSObjectProtocol] = []
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
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }

        func deliverIfAttached(_ action: @escaping () -> Void) {
            let generation = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.generation == generation else { return }
                action()
            }
        }

        private func cancelRecording() {
            stopRecording()
            onCancel?()
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
