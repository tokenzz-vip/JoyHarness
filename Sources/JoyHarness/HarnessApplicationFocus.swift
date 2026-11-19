import Foundation

/// Chooses between focusing a running Harness and launching it first.
@MainActor
enum HarnessApplicationFocus {
    static func perform(
        installedURL: URL?,
        runningProcessID: Int32?,
        focusRunning: @escaping (Int32) -> Void,
        launch: @escaping (URL, @escaping (Int32?) -> Void) -> Void
    ) {
        guard let installedURL else { return }
        if let runningProcessID {
            focusRunning(runningProcessID)
            return
        }
        launch(installedURL) { processID in
            guard let processID else { return }
            focusRunning(processID)
        }
    }
}
