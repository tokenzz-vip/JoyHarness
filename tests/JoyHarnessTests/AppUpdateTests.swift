import Foundation
import Sparkle
import Testing
@testable import JoyHarness

@MainActor
struct AppUpdateTests {
    @Test func localAndSameVersionsDoNotOfferUpdates() throws {
        let older = try release(version: "0.1.0", build: "999")
        let same = try release(version: "0.1.1", build: "999")
        #expect(AppUpdateReleasePolicy.bestUpdate(in: [older], currentVersion: "0.1.1")
            === SUAppcastItem.empty())
        #expect(AppUpdateReleasePolicy.bestUpdate(in: [same], currentVersion: "0.1.1")
            === SUAppcastItem.empty())
    }

    @Test func newerDisplayVersionWinsRegardlessOfFeedOrder() throws {
        let next = try release(version: "0.1.10", build: "20")
        let latest = try release(version: "0.2.0", build: "1000")
        for items in [[latest, next], [next, latest]] {
            #expect(AppUpdateReleasePolicy.bestUpdate(
                in: items,
                currentVersion: "0.1.9"
            ) === latest)
        }
    }

    @Test func newestBuildWinsWithinTheSameRelease() throws {
        let first = try release(version: "0.2.0", build: "20")
        let second = try release(version: "0.2.0", build: "21")
        #expect(AppUpdateReleasePolicy.bestUpdate(
            in: [second, first],
            currentVersion: "0.1.9"
        ) === second)
    }

    @Test func configurationRequiresHTTPSAndEd25519PublicKey() {
        let key = Data(repeating: 7, count: 32).base64EncodedString()
        #expect(AppUpdateModel.hasValidConfiguration([
            "SUFeedURL": "https://example.com/appcast-arm64.xml",
            "SUPublicEDKey": key,
        ]))
        #expect(!AppUpdateModel.hasValidConfiguration([:]))
        #expect(!AppUpdateModel.hasValidConfiguration([
            "SUFeedURL": "http://example.com/appcast-arm64.xml",
            "SUPublicEDKey": key,
        ]))
        #expect(!AppUpdateModel.hasValidConfiguration([
            "SUFeedURL": "https://example.com/appcast-arm64.xml",
            "SUPublicEDKey": "placeholder",
        ]))
    }

    @Test func checksAreGatedAndSparklePreferencesStayInSync() {
        let driver = UpdateDriverStub()
        let model = AppUpdateModel()
        model.checkForUpdates()
        model.start(driver: driver)
        #expect(model.isConfigured)
        #expect(model.canCheckForUpdates)
        model.checkForUpdates()
        #expect(driver.checks == 1)
        #expect(!model.canCheckForUpdates)

        let checkedAt = Date(timeIntervalSince1970: 123)
        driver.lastUpdateCheckDate = checkedAt
        driver.canCheckForUpdates = true
        driver.onChange?()
        #expect(model.lastUpdateCheckDate == checkedAt)
        model.setAutomaticallyChecksForUpdates(true)
        #expect(driver.automaticallyChecksForUpdates)
        #expect(model.automaticallyChecksForUpdates)
    }

    @Test func startFailureCanBeRetried() {
        let failed = UpdateDriverStub()
        failed.startError = NSError(domain: "test", code: 1)
        let model = AppUpdateModel()
        model.start(driver: failed)
        #expect(!model.isConfigured)
        #expect(!model.canCheckForUpdates)
        #expect(model.errorMessage != nil)
        #expect(failed.onChange == nil)

        model.start(driver: UpdateDriverStub())
        #expect(model.isConfigured)
        #expect(model.canCheckForUpdates)
        #expect(model.errorMessage == nil)
    }

    private func release(version: String, build: String) throws -> SUAppcastItem {
        try #require(SUAppcastItem(dictionary: [
            "sparkle:version": build,
            "sparkle:shortVersionString": version,
            "enclosure": ["url": "https://example.com/JoyHarness-\(version).dmg"],
        ]))
    }
}

@MainActor
private final class UpdateDriverStub: AppUpdateDriving {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = false
    var lastUpdateCheckDate: Date?
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var checks = 0
    var startError: Error?

    func start() throws {
        if let startError { throw startError }
    }

    func checkForUpdates() {
        checks += 1
        canCheckForUpdates = false
        onChange?()
    }
}
