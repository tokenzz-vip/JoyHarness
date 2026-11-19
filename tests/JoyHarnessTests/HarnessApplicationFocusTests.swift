import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct HarnessApplicationFocusTests {
    @Test func missingApplicationDoesNothing() {
        var focused = false
        var launched = false
        HarnessApplicationFocus.perform(installedURL: nil, runningProcessID: nil,
                                        focusRunning: { _ in focused = true },
                                        launch: { _, _ in launched = true })
        #expect(!focused)
        #expect(!launched)
    }

    @Test func runningApplicationIsFocusedWithoutLaunching() {
        var focusedProcessID: Int32?
        var launched = false
        HarnessApplicationFocus.perform(installedURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"), runningProcessID: 42,
                                        focusRunning: { focusedProcessID = $0 },
                                        launch: { _, _ in launched = true })
        #expect(focusedProcessID == 42)
        #expect(!launched)
    }

    @Test func installedApplicationIsLaunchedAndThenFocused() {
        let url = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        var launchedURL: URL?
        var focusedProcessID: Int32?
        HarnessApplicationFocus.perform(installedURL: url, runningProcessID: nil,
                                        focusRunning: { focusedProcessID = $0 },
                                        launch: { requestedURL, completion in
            launchedURL = requestedURL
            completion(84)
        })
        #expect(launchedURL == url)
        #expect(focusedProcessID == 84)
    }

    @Test func composerFocusWaitsForForegroundAndEditor() {
        let clock = TestClock()
        var state = HarnessComposerFocus.AppState.waiting
        var editorReady = false
        var attempts: [(Int32, HarnessFocusTarget)] = []
        let focus = HarnessComposerFocus(state: { _ in state }, focusComposer: { processID, target in
            attempts.append((processID, target)); return editorReady
        }, schedule: clock.schedule)

        focus.start(processID: 42, target: .cursor)
        #expect(attempts.isEmpty)
        state = .frontmost
        clock.advance(0.25)
        #expect(attempts.count == 1)
        editorReady = true
        clock.advance(0.25)
        clock.advance(5)
        #expect(attempts.count == 2)
        #expect(attempts.allSatisfy { $0.1 == .cursor })
    }

    @Test func activationReportsUnavailableAndFailedStates() {
        #expect(HarnessApplicationActivation.perform(isAvailable: { false }, requestActivation: { true }, makeFrontmost: { true }, requestReopen: { true }) == .unavailable)
        #expect(HarnessApplicationActivation.perform(isAvailable: { true }, requestActivation: { false }, makeFrontmost: { false }, requestReopen: { true }) == .failed)
        #expect(HarnessApplicationActivation.perform(isAvailable: { true }, requestActivation: { true }, makeFrontmost: { false }, requestReopen: { true }) == .activated)
    }
}
