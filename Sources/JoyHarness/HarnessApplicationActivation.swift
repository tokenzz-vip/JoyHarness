import AppKit
import ApplicationServices

/// Activates an existing application and asks it to reopen its main window.
@MainActor
enum HarnessApplicationActivation {
    enum Result: Equatable { case activated, unavailable, failed }

    static func perform(processID: Int32, isAvailable: () -> Bool) -> Result {
        perform(isAvailable: isAvailable, requestActivation: {
            guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else { return false }
            application.unhide()
            NSApp.yieldActivation(to: application)
            return application.activate(options: [.activateAllWindows]) || application.isActive
        }, makeFrontmost: {
            guard AXIsProcessTrusted() else { return false }
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(application, 0.5)
            let error = AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if error != .success {
                Log.app.error("Harness focus failed pid=\(processID) accessibility_error=\(error.rawValue)")
            }
            return error == .success
        }, requestReopen: {
            reopen(processID: processID)
        })
    }

    static func perform(isAvailable: () -> Bool, requestActivation: () -> Bool,
                        makeFrontmost: () -> Bool, requestReopen: () -> Bool) -> Result {
        guard isAvailable() else { return .unavailable }
        if !requestActivation() {
            guard isAvailable(), makeFrontmost() else { return .failed }
        }
        guard isAvailable() else { return .unavailable }
        return requestReopen() ? .activated : .failed
    }

    private static func reopen(processID: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processID), !application.isTerminated else { return false }
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        do {
            _ = try event.sendEvent(options: [.noReply, .canInteract], timeout: 0.5)
            return true
        } catch {
            Log.app.error("Harness reopen failed pid=\(processID) error=\(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}
