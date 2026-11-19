import Foundation
import Testing
@testable import JoyHarness

@MainActor
struct PhraseTests {
    private func snapshot(_ buttons: Set<ControllerInput> = [], x: Int = 2048, y: Int = 2048) -> JoyConSnapshot {
        .init(buttons: buttons, stick: .init(x: x, y: y), battery: nil, charging: false)
    }

    @Test func defaultsMatchRcHarnessLibraryAndAssignments() throws {
        #expect(DefaultPhrases.all.count == 16)
        #expect(DefaultPhrases.all.first?.title == "继续执行")
        let assignments = DefaultPhrases.assignments(for: DefaultPhrases.all)
        #expect(PhraseAssignments.inputs.allSatisfy { assignments[$0] != nil })
        var config = Configuration(); config.phrases = DefaultPhrases.all; config.phraseAssignments = assignments
        let copy = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(copy.phrases == DefaultPhrases.all)
        #expect(copy.phraseAssignments == assignments)
    }

    @Test func upgradesAnExistingEmptyLibraryAndKeepsLaterDeletions() throws {
        let suite = "JoyHarness.PhrasePresetsTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStorage.save(Configuration(), "configuration.v1", defaults: defaults)

        let upgraded = DashboardModel(defaults: defaults, preview: true)
        #expect(upgraded.configuration.phrases == DefaultPhrases.all)
        #expect(upgraded.configuration.phraseAssignments == DefaultPhrases.assignments(for: DefaultPhrases.all))

        var emptied = upgraded.configuration
        emptied.phrases.removeAll()
        emptied.phraseAssignments = .init()
        upgraded.configuration = emptied

        let relaunched = DashboardModel(defaults: defaults, preview: true)
        #expect(relaunched.configuration.phrases.isEmpty)
        #expect(relaunched.configuration.phraseAssignments.slots.isEmpty)
    }

    @Test func upgradesWithoutDuplicatingEditsOrReplacingExistingAssignments() throws {
        var edited = DefaultPhrases.all[0]
        edited.title = "我的继续执行"
        edited.text = "继续"
        var equivalent = DefaultPhrases.all[1]
        equivalent.id = UUID()
        var legacy = Configuration()
        legacy.phrases = [edited, equivalent]
        legacy.phraseAssignments[.up] = equivalent.id

        let upgraded = try legacy.addingBuiltInPhrases().validated()
        #expect(upgraded.phrases.count == DefaultPhrases.all.count)
        #expect(Array(upgraded.phrases.prefix(2)) == legacy.phrases)
        #expect(upgraded.phraseAssignments == legacy.phraseAssignments)
        #expect(upgraded.addingBuiltInPhrases() == upgraded)
    }

    @Test func pickerUsesChineseSingleTapAndEnglishDoubleTap() {
        let clock = TestClock()
        let picker = PhrasePickerModel(schedule: clock.schedule)
        let phrase = DefaultPhrases.all[0]
        var output: [String] = []
        picker.onOutput = { output.append($0) }
        picker.present(phrases: [phrase], assignments: { var value = PhraseAssignments(); value[.up] = phrase.id; return value }())
        picker.receive(snapshot([.up]), center: nil, deadzone: 0.18)
        picker.receive(snapshot(), center: nil, deadzone: 0.18)
        clock.advance(0.31)
        #expect(output == [phrase.text])

        picker.present(phrases: [phrase], assignments: { var value = PhraseAssignments(); value[.up] = phrase.id; return value }())
        for _ in 0..<2 {
            picker.receive(snapshot(y: 4095), center: nil, deadzone: 0.18)
            picker.receive(snapshot(), center: nil, deadzone: 0.18)
        }
        #expect(output == [phrase.text, phrase.englishText])
    }

    @Test func openingInputsAndStickRollDoNotSelectExtraPhrases() {
        let clock = TestClock()
        let picker = PhrasePickerModel(schedule: clock.schedule)
        let phrases = DefaultPhrases.all
        var output: [String] = []
        picker.onOutput = { output.append($0) }
        picker.present(phrases: phrases, assignments: DefaultPhrases.assignments(for: phrases))

        picker.receive(snapshot([.rightStick], x: 4095), center: nil, deadzone: 0.18, baseline: true)
        picker.receive(snapshot(), center: nil, deadzone: 0.18)
        clock.advance(0.31)
        #expect(output.isEmpty)
        #expect(picker.isPresented)

        picker.receive(snapshot(x: 4095), center: nil, deadzone: 0.18)
        picker.receive(snapshot(y: 4095), center: nil, deadzone: 0.18)
        #expect(picker.selectedInput == .right)
        picker.receive(snapshot(), center: nil, deadzone: 0.18)
        clock.advance(0.31)
        #expect(output == [phrases[9].text])
    }

    @Test func cancelDiscardsPendingSelection() {
        let clock = TestClock()
        let picker = PhrasePickerModel(schedule: clock.schedule)
        let phrases = DefaultPhrases.all
        var output: [String] = []
        picker.onOutput = { output.append($0) }
        for input in [ControllerInput.b, .home, .minus] {
            picker.present(phrases: phrases, assignments: DefaultPhrases.assignments(for: phrases))
            picker.click(.up)
            picker.receive(snapshot([input]), center: nil, deadzone: 0.18)
            clock.advance(0.31)
            #expect(!picker.isPresented)
            #expect(output.isEmpty)
        }
    }

    @Test func captureReleasesHoldsAndSuppressesHeldInputsUntilNeutral() {
        let clock = TestClock()
        let engine = InputEngine(schedule: clock.schedule, now: { clock.time })
        let controller = JoyConProfile.all[1]
        let id = controller.id
        var profile = KeyProfile()
        profile.mapping[.r] = .init(action: .enter)
        engine.configure(profile: profile, deadzone: 0.18, speed: 14, centers: [:])
        engine.selectDevice(id, baseline: snapshot())
        engine.cycleStickMode(for: .right)
        var actions: [Bool] = []
        var moves = 0
        engine.output = { mapping, pressed in
            if mapping.action == .enter { actions.append(pressed) }
        }
        engine.pointer = { _, _ in moves += 1 }

        engine.receive(id: id, profile: controller, snapshot: snapshot([.r]))
        engine.setInputCaptured(true)
        engine.receive(id: id, profile: controller, snapshot: snapshot([.r], x: 4095))
        engine.tick()
        #expect(actions == [true, false])
        #expect(moves == 0)

        engine.setInputCaptured(false)
        engine.receive(id: id, profile: controller, snapshot: snapshot([.r], x: 4095))
        engine.tick()
        #expect(actions == [true, false])
        #expect(moves == 0)

        engine.receive(id: id, profile: controller, snapshot: snapshot())
        engine.receive(id: id, profile: controller, snapshot: snapshot([.r], x: 4095))
        engine.tick()
        #expect(actions == [true, false, true])
        #expect(moves == 1)
    }
}

