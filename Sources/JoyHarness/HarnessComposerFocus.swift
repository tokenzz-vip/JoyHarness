import AppKit
import ApplicationServices

@MainActor
final class HarnessComposerFocus {
    enum AppState { case waiting, frontmost, exited }

    private let state: (Int32) -> AppState
    private let focusComposer: (Int32, HarnessFocusTarget) -> Bool
    private let schedule: CommandQueue.Scheduler
    private var pending: DispatchWorkItem?

    init() {
        state = { processID in
            guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else { return .exited }
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == processID ? .frontmost : .waiting
        }
        focusComposer = Self.focusInCurrentWindow
        schedule = CommandQueue.mainQueue
    }

    init(state: @escaping (Int32) -> AppState, focusComposer: @escaping (Int32, HarnessFocusTarget) -> Bool,
         schedule: @escaping CommandQueue.Scheduler) {
        self.state = state; self.focusComposer = focusComposer; self.schedule = schedule
    }

    func start(processID: Int32, target: HarnessFocusTarget) {
        cancel(); attempt(processID: processID, target: target, remaining: 20, wasFrontmost: false)
    }

    func cancel() { pending?.cancel(); pending = nil }

    private func attempt(processID: Int32, target: HarnessFocusTarget, remaining: Int, wasFrontmost: Bool) {
        pending = nil
        let current = state(processID)
        guard current != .exited, current == .frontmost || !wasFrontmost else { return }
        if current == .frontmost, focusComposer(processID, target) { return }
        guard remaining > 1 else { return }
        pending = schedule(0.25) { [weak self] in
            self?.attempt(processID: processID, target: target, remaining: remaining - 1,
                          wasFrontmost: wasFrontmost || current == .frontmost)
        }
    }

    private static func focusInCurrentWindow(processID: Int32, target: HarnessFocusTarget) -> Bool {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.1)
        if target != .chatgpt {
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        if let focused = element(application, kAXFocusedUIElementAttribute), isComposer(focused, target: target) { return true }
        guard let window = element(application, kAXFocusedWindowAttribute) ?? element(application, kAXMainWindowAttribute) else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        var nodes = [window]
        for _ in 0..<1_500 {
            guard ProcessInfo.processInfo.systemUptime < deadline, let node = nodes.popLast() else { return false }
            if isComposer(node, target: target), attribute(node, kAXEnabledAttribute) as? Bool != false {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return false }
                let result = AXUIElementSetAttributeValue(node, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                if result == .success { return attribute(node, kAXFocusedAttribute) as? Bool == true }
            }
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { nodes.append(contentsOf: children) }
        }
        return false
    }

    private static func isComposer(_ node: AXUIElement, target: HarnessFocusTarget) -> Bool {
        guard attribute(node, kAXRoleAttribute) as? String == kAXTextAreaRole else { return false }
        let classes = attribute(node, "AXDOMClassList") as? [String] ?? []
        switch target {
        case .chatgpt:
            return classes.contains("ProseMirror") && hasAncestor(node, depth: 1) { $0 == "ComposerLayoutBody" || $0.hasPrefix("ComposerLayoutBody-") }
        case .claude:
            return classes.contains("ProseMirror") && (attribute(node, kAXDescriptionAttribute) as? String == "Prompt" || hasAncestor(node, depth: 6) { $0 == "rounded-composer" })
        case .cursor: return classes.contains("ui-prompt-input-editor__input")
        case .deepSeek: return hasAncestor(node, depth: 4) { $0.hasSuffix("_composerSeat") }
        case .workBuddy: return hasAncestor(node, depth: 3) { $0 == "cr-input-container" }
        case .openCode: return hasAncestor(node, depth: 3) { $0 == "group/composer" }
        }
    }

    private static func hasAncestor(_ node: AXUIElement, depth: Int, matching: (String) -> Bool) -> Bool {
        var current = node
        for _ in 0..<depth {
            guard let parent = element(current, kAXParentAttribute) else { return false }
            let classes = attribute(parent, "AXDOMClassList") as? [String] ?? []
            if classes.contains(where: matching) { return true }
            current = parent
        }
        return false
    }

    private static func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
}
