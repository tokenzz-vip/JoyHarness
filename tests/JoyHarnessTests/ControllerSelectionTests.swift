import Foundation
import Testing
@testable import JoyHarness

@MainActor
private final class FakeTransport: ControllerTransport {
    var onDevice: ((ConnectedJoyCon) -> Void)?
    var onInput: ((String, JoyConProfile, JoyConSnapshot) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    func start() {}
    func stop() {}
    func announce(_ id: String, _ profile: JoyConProfile, ready: Bool = true) {
        onDevice?(.init(id: id, profile: profile, ready: ready))
    }
    func send(_ id: String, _ profile: JoyConProfile, buttons: Set<ControllerInput> = [], x: Int = 2048) {
        onInput?(id, profile, .init(buttons: buttons, stick: .init(x: x, y: 2048), battery: 75, charging: false))
    }
}

@MainActor
struct ControllerSelectionTests {
    private func snapshot(_ buttons: Set<ControllerInput> = [], x: Int = 2048) -> JoyConSnapshot {
        .init(buttons: buttons, stick: .init(x: x, y: 2048), battery: 75, charging: false)
    }

    @Test func setupCapturesOnlyFreshInputFromTheSelectedController() throws {
        let suite = "JoyHarness.test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FakeTransport(), engine = InputEngine()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport], inputEngine: engine)
        let first = JoyConProfile.all[0], second = JoyConProfile.all[3]
        model.accessibility = true
        model.inputMonitoring = true
        transport.announce("one", first)
        transport.announce("other", second)
        var events: [Bool] = []
        engine.output = { _, pressed in events.append(pressed) }
        transport.send("one", first)
        transport.send("one", first, buttons: [.up])
        #expect(events == [true])

        model.presentSetup()
        #expect(events == [true, false])
        model.advanceSetup()
        model.selectDevice("other")
        model.advanceSetup()
        #expect(model.setup.step == .permissions)
        model.selectDevice("one")
        for _ in 0..<3 { model.advanceSetup() }
        #expect(model.setup.step == .trial)

        transport.send("other", second, buttons: [.a])
        transport.send("one", first, buttons: [.up])
        #expect(model.setup.testedButtons.isEmpty)
        transport.send("one", first)
        transport.send("one", first, buttons: [.up])
        #expect(model.setup.testedButtons == [.up])
        model.advanceSetup()
        #expect(model.setup.step == .complete)
        model.pauseSetup()
        #expect(SetupFlow(defaults: defaults).step == .trial)
        #expect(model.setup.testedButtons.isEmpty)
        transport.send("one", first, buttons: [.up])
        transport.send("one", first)
        #expect(events == [true, false])
        transport.send("one", first, buttons: [.up])
        #expect(events == [true, false, true])

        model.presentSetup()
        transport.send("one", first)
        transport.send("one", first, buttons: [.up])
        model.advanceSetup()
        transport.onDisconnect?("one")
        model.advanceSetup()
        #expect(!model.setup.completed)
        model.setup.goBack(to: .trial)
        transport.announce("one", first)
        transport.send("one", first)
        transport.send("one", first, buttons: [.up])
        model.advanceSetup()
        model.advanceSetup()
        #expect(SetupFlow(defaults: defaults).completed)
        #expect(model.page == .mapping)
        model.presentSetup()
        #expect(model.setup.step == .welcome)
        model.pauseSetup()
        #expect(SetupFlow(defaults: defaults).completed)
    }
    @Test func firstReadyDeviceBindsOnceAndSameModelIsDistinct() throws {
        let profile = JoyConProfile.all[0]
        var selection = ControllerSelection()
        let notReady = selection.discover(.init(id: "one", profile: profile))
        #expect(!notReady)
        let bound = selection.discover(.init(id: "two", profile: profile, ready: true))
        #expect(bound)
        let ignored = selection.discover(.init(id: "one", profile: profile, ready: true))
        #expect(!ignored)
        #expect(selection.deviceID == "two")
        let restored = try JSONDecoder().decode(ControllerSelection.self, from: JSONEncoder().encode(selection))
        #expect(restored == selection)
    }
    @Test func offlineModelChoiceWaitsForMatchingGenerationAndSide() {
        var selection = ControllerSelection()
        selection.selectProfile(JoyConProfile.all[3])
        for profile in JoyConProfile.all.prefix(3) {
            let ignored = selection.discover(.init(id: profile.id, profile: profile, ready: true))
            #expect(!ignored)
        }
        let bound = selection.discover(.init(id: "right-2", profile: JoyConProfile.all[3], ready: true))
        #expect(bound)
    }
    @Test func switchingReleasesHoldsStopsStickAndRequiresFreshInput() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        let profile = JoyConProfile.all[0]
        var events: [String] = [], moves = 0
        engine.output = { events.append("\($0.action.rawValue):\($1)") }
        engine.pointer = { x, y in if x != 0 || y != 0 { moves += 1 } }
        engine.selectDevice("one", baseline: snapshot())
        engine.cycleStickMode(for: .left)
        engine.receive(id: "one", profile: profile, snapshot: snapshot([.zl], x: 4095))
        engine.tick()
        #expect(events == ["mouseRight:true"]); #expect(moves == 1)
        engine.selectDevice("two", baseline: snapshot([.zl], x: 4095))
        #expect(engine.stickMode(for: .left) == .mapped)
        engine.cycleStickMode(for: .left)
        engine.tick()
        #expect(events == ["mouseRight:true", "mouseRight:false"]); #expect(moves == 1)
        engine.receive(id: "one", profile: profile, snapshot: snapshot([.l], x: 4095))
        engine.receive(id: "two", profile: profile, snapshot: snapshot([.zl], x: 4095))
        engine.tick(); #expect(events.count == 2); #expect(moves == 1)
        engine.receive(id: "two", profile: profile, snapshot: snapshot())
        engine.receive(id: "two", profile: profile, snapshot: snapshot([.zl], x: 4095))
        engine.tick(); #expect(events.last == "mouseRight:true"); #expect(moves == 2)
    }
    @Test func selectionCancelsPendingSingleDoubleAndLongGestures() {
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        var profile = KeyProfile()
        profile.mapping[.a, .double] = .init(action: .copy)
        profile.mapping[.b, .long] = .init(action: .paste)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        var events = 0; engine.output = { _, _ in events += 1 }
        engine.selectDevice("one", baseline: snapshot())
        engine.receive(id: "one", profile: JoyConProfile.all[1], snapshot: snapshot([.a, .b]))
        engine.receive(id: "one", profile: JoyConProfile.all[1], snapshot: snapshot([.b]))
        engine.selectDevice("two", baseline: snapshot())
        clock.advance(1); #expect(events == 0)
    }
    @Test func noSelectionAndNonSelectedRecoveryButtonsAreIgnored() {
        let engine = InputEngine()
        var events = 0; engine.output = { _, _ in events += 1 }
        engine.receive(id: "other", profile: JoyConProfile.all[1], snapshot: snapshot([.home]))
        engine.selectDevice("selected", baseline: snapshot())
        engine.setEnabled(false)
        engine.receive(id: "other", profile: JoyConProfile.all[1], snapshot: snapshot([.home]))
        #expect(events == 0)
        engine.receive(id: "selected", profile: JoyConProfile.all[1], snapshot: snapshot([.home]))
        #expect(events == 1)
    }
    @Test func modelRoutesBothGenerationsAndPersistsPhysicalSelection() {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FakeTransport(), engine = InputEngine()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport], inputEngine: engine)
        var events: [String] = []
        engine.output = { events.append("\($0.action.rawValue):\($1)") }
        let first = JoyConProfile.all[1], second = JoyConProfile.all[3]
        transport.announce("first", first); transport.send("first", first)
        transport.announce("second", second); transport.send("second", second)
        transport.send("second", second, buttons: [.a])
        #expect(events.isEmpty); #expect(model.pressed.isEmpty)
        transport.send("first", first, buttons: [.a])
        #expect(events == ["enter:true"])
        model.selectDevice("second")
        #expect(events == ["enter:true", "enter:false"])
        transport.send("second", second, buttons: [.a]); #expect(events.count == 2)
        transport.send("second", second)
        transport.send("second", second, buttons: [.a])
        #expect(events.last == "enter:true"); #expect(model.pressed == [.a])
        transport.onDisconnect?("first"); #expect(events.last == "enter:true")
        #expect(model.connectedDevices.map(\.id) == ["second"])
        transport.onDisconnect?("second"); #expect(events.last == "enter:false"); #expect(model.pressed.isEmpty)
        #expect(model.connectedDevices.isEmpty)
        transport.announce("first", first)
        #expect(model.controllerSelection.deviceID == "second"); #expect(!model.selectedDeviceReady)
        let restored = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(restored.controllerSelection.deviceID == "second")
        transport.announce("second", second); transport.send("second", second, buttons: [.a])
        #expect(model.connectedDevices.map(\.id) == ["first", "second"])
        #expect(events.last == "enter:false")
        transport.send("second", second); transport.send("second", second, buttons: [.a])
        #expect(events.last == "enter:true")
    }
    @Test(arguments: [false, true])
    func inputSuspensionKeepsConnectedControllerReady(importingConfiguration: Bool) {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(), engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        let transport = FakeTransport()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport], inputEngine: engine)
        let profile = JoyConProfile.all[1]
        var events: [String] = []
        engine.output = { events.append("\($0.action.rawValue):\($1)") }
        transport.announce("one", profile)
        transport.send("one", profile)
        transport.send("one", profile, buttons: [.a])
        #expect(events == ["enter:true"])

        if importingConfiguration {
            model.pendingConfigurationImport = .init(source: "test", isRecovery: false, configuration: model.configuration)
        } else {
            model.beginEditing()
        }
        #expect(events == ["enter:true", "enter:false"])
        for _ in 0..<5 {
            clock.advance(0.5)
            transport.announce("one", profile)
            transport.send("one", profile, buttons: [.a])
            engine.tick()
            #expect(model.selectedDeviceReady)
        }

        if importingConfiguration {
            model.pendingConfigurationImport = nil
        } else {
            model.endEditing()
        }
        transport.send("one", profile, buttons: [.a])
        #expect(events == ["enter:true", "enter:false"])
        transport.send("one", profile)
        transport.send("one", profile, buttons: [.a])
        #expect(events == ["enter:true", "enter:false", "enter:true"])
        transport.onDisconnect?("one")
        #expect(!model.selectedDeviceReady)
        #expect(events.last == "enter:false")
    }
    @Test func mappingInputsMatchStandaloneJoyCon() {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true, transports: [])
        for profile in JoyConProfile.all {
            model.selectControllerProfile(profile)
            #expect(model.controllerInputs.allSatisfy { $0.side == profile.side })
            #expect(!model.controllerInputs.contains(.gl))
            #expect(!model.controllerInputs.contains(.gr))
            #expect(model.controllerInputs.contains(.c) == (profile.generation == .second && profile.side == .right))
            if profile.generation == .first { #expect(!model.controllerInputs.contains { $0.secondGenerationOnly }) }
        }
    }
}

@MainActor
struct ControllerMenuTests {
    @Test func nativeMenuDistinguishesEqualModelsAndTracksSelection() throws {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FakeTransport()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport])
        let profile = JoyConProfile.all[3]
        transport.announce("ble-device-111111", profile)
        transport.announce("ble-device-222222", profile)
        model.selectDevice("ble-device-222222")
        let menu = ControllerDeviceMenuContent.make(model: model, target: nil, action: nil)
        let waitingIDs = JoyConProfile.all.dropLast().map { "profile:" + $0.id }
        #expect(menu.items.compactMap { $0.representedObject as? String } == waitingIDs + ["ble-device-111111", "ble-device-222222"])
        let items = menu.items.filter { ($0.representedObject as? String)?.hasPrefix("ble-device-") == true }
        #expect(items.count == 2)
        #expect(items.map { $0.title.components(separatedBy: "\t")[0] } == ["Joy-Con 2 (R) · 111111", "Joy-Con 2 (R) · 222222"])
        #expect(items[0].state == .off); #expect(items[1].state == .on)
        #expect(items[0].isEnabled); #expect(!items[1].isEnabled)
        #expect(model.controllerTitle == "Joy-Con 2 (R) · 222222")
        transport.onDisconnect?("ble-device-111111")
        let afterDisconnect = ControllerDeviceMenuContent.make(model: model, target: nil, action: nil)
        #expect(afterDisconnect.items.compactMap { $0.representedObject as? String } == waitingIDs + ["ble-device-222222"])
        model.selectDevice("ble-device-111111")
        #expect(model.controllerSelection.deviceID == "ble-device-222222")
        #expect(model.selectedDeviceReady)
        #expect(model.controllerTitle == "Joy-Con 2 (R)")

        transport.onDisconnect?("ble-device-222222")
        let emptyMenu = ControllerDeviceMenuContent.make(model: model, target: nil, action: nil)
        let waitingItems = emptyMenu.items.filter { $0.representedObject != nil }
        #expect(waitingItems.compactMap { $0.representedObject as? String } == JoyConProfile.all.map { "profile:" + $0.id })
        #expect(waitingItems.map { $0.title.components(separatedBy: "\t")[0] } == JoyConProfile.all.map(\.name))
        #expect(waitingItems.allSatisfy { $0.isEnabled })
        #expect(model.controllerSelection.deviceID == "ble-device-222222")
        #expect(model.controllerTitle == "Joy-Con 2 (R)")

        transport.announce("ble-device-222222", profile)
        let afterReconnect = ControllerDeviceMenuContent.make(model: model, target: nil, action: nil)
        let reconnectedItems = afterReconnect.items.filter { $0.representedObject != nil }
        #expect(reconnectedItems.compactMap { $0.representedObject as? String } == waitingIDs + ["ble-device-222222"])
        #expect(reconnectedItems.last?.state == .on)
        #expect(model.controllerTitle == "Joy-Con 2 (R)")
        #expect(model.statistics.total == 0)

        let waitingItem = try #require(reconnectedItems.first)
        ControllerDeviceMenuContent.select(waitingItem, model: model)
        #expect(model.controllerSelection.profile == JoyConProfile.all[0])
        #expect(model.controllerSelection.deviceID == nil)
    }
    @Test func preferencesNamesAndStatisticsPersistWithoutPreviewSideEffects() {
        let suite = "JoyHarness.tests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(model.colorMode == .iris)
        model.colorMode = .safari
        model.themeMode = .dark; model.showDockIcon = false; model.openAtLaunch = false
        #expect(model.profileNameError("   ") != nil)
        let saved = model.saveProfile(name: "  浏览器  ")
        #expect(saved); #expect(model.selectedProfile.name == "浏览器")
        #expect(model.profileNameError("浏览器") != nil)
        let longName = String(repeating: "长", count: 80)
        let renamed = model.saveProfile(name: longName, replacing: model.selectedProfileID)
        #expect(renamed)
        model.duplicateProfile()
        #expect(model.selectedProfile.name.count <= 80)
        let browser = model.saveProfile(name: "浏览器")
        #expect(browser)
        model.statistics.record(.a); model.clearStatistics()
        let restored = DashboardModel(defaults: defaults, preview: true, transports: [])
        #expect(restored.colorMode == .safari)
        #expect(restored.themeMode == .dark); #expect(!restored.showDockIcon); #expect(!restored.openAtLaunch)
        #expect(restored.selectedProfile.name == "浏览器"); #expect(restored.statistics.total == 0)
        defaults.set("unknown-palette", forKey: "JoyHarness.colorMode")
        #expect(DashboardModel(defaults: defaults, preview: true, transports: []).colorMode == .iris)
    }
}

extension ControllerSelectionTests {
    @Test func staleControllerSelectionRequiresReleaseAndNeutral() {
        let suite = "JoyHarness.StaleSelection.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = TestClock(), transport = FakeTransport(), engine = InputEngine(now: { clock.time })
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport],
                                   inputEngine: engine, now: { clock.time })
        let profile = JoyConProfile.all[3]
        var actions: [RemoteAction] = []
        engine.output = { if $1 { actions.append($0.action) } }
        transport.announce("one", profile)
        transport.send("one", profile)
        transport.announce("two", profile)
        transport.send("two", profile)
        clock.advance(2.1)
        model.selectDevice("two")
        #expect(!model.selectedDeviceReady)
        transport.announce("two", profile)
        transport.send("two", profile, buttons: [.c], x: 4095)
        #expect(actions.isEmpty)
        transport.send("two", profile)
        transport.send("two", profile, buttons: [.c], x: 4095)
        #expect(actions == [.rightCommand, .arrowRight])
    }

    @Test func stableHIDIdentityMigratesSelectionAndCenter() {
        let suite = "JoyHarness.HIDIdentity.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FakeTransport()
        let model = DashboardModel(defaults: defaults, preview: true, transports: [transport])
        let profile = JoyConProfile.all[0]
        transport.announce("previous", profile)
        transport.send("previous", profile, x: 2010)
        if let device = model.selectedDevice { model.calibrate(device) }
        transport.onDisconnect?("previous")
        transport.onDevice?(.init(id: "stable", profile: profile, ready: true, previousID: "previous"))
        #expect(model.controllerSelection.deviceID == "stable")
        #expect(model.configuration.centers["stable"] == .init(x: 2010, y: 2048))
    }
}
