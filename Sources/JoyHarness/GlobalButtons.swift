import Foundation

struct GlobalButton: Codable, Equatable, Identifiable {
    var id = UUID()
    var input: ControllerInput?
    var actions: [Gesture: ButtonMapping] = [:]
}

struct VoiceButton: Codable, Equatable {
    var input: ControllerInput?
    var mode: VoiceTriggerMode = .hold
    var holdKey: VoiceShortcutKey = .function
    var tapKeys: Set<VoiceShortcutKey> = [.function]

    var shortcut: VoiceShortcut {
        .init(mode: mode, keys: mode == .hold ? [holdKey] : tapKeys)
    }

    private enum CodingKeys: String, CodingKey { case input, mode, holdKey, tapKeys }

    init(input: ControllerInput?) { self.input = input }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        input = try values.decodeIfPresent(ControllerInput.self, forKey: .input)
        mode = try values.decodeIfPresent(VoiceTriggerMode.self, forKey: .mode) ?? .hold
        holdKey = try values.decodeIfPresent(VoiceShortcutKey.self, forKey: .holdKey) ?? .function
        tapKeys = try values.decodeIfPresent(Set<VoiceShortcutKey>.self, forKey: .tapKeys) ?? [.function]
    }
}

extension JoyConProfile {
    var defaultVoiceInput: ControllerInput { side == .left ? .leftSL : .rightSR }

    var physicalInputs: [ControllerInput] {
        ControllerInput.allCases.filter {
            $0.side == side && !$0.isStickDirection && $0 != .gl && $0 != .gr
                && (generation == .second || !$0.secondGenerationOnly)
        }
    }
}

extension Configuration {
    static let defaultVoiceButtons = Dictionary(uniqueKeysWithValues: JoyConProfile.all.map {
        ($0.id, VoiceButton(input: $0.defaultVoiceInput))
    })

    func voiceInputChoices(for profile: JoyConProfile) -> [ControllerInput] {
        let globals = Set(globalButtons[profile.id, default: []].compactMap(\.input))
        let mouse = mouseButtons[profile.id] ?? .init()
        return profile.physicalInputs.filter { !globals.contains($0) && $0 != mouse.left && $0 != mouse.right }
    }

    static func defaultGlobalButtons(from mapping: RemoteMapping) -> [String: [GlobalButton]] {
        Dictionary(uniqueKeysWithValues: JoyConProfile.all.map { profile in
            let inputs: [ControllerInput] = profile.side == .left ? [.minus, .capture] : [.plus, .home]
            let buttons = inputs.map { input in
                var actions = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0, mapping[input, $0]) })
                if input == .minus || input == .plus {
                    for gesture in [Gesture.double, .long] where actions[gesture] == ButtonMapping() {
                        actions[gesture] = nil
                    }
                }
                return GlobalButton(input: input, actions: actions)
            }
            return (profile.id, buttons)
        })
    }

    static func migratingFactoryGlobalGestures(_ groups: [String: [GlobalButton]]) -> [String: [GlobalButton]] {
        groups.mapValues { buttons in
            buttons.map { button in
                guard let input = button.input, input == .minus || input == .plus else { return button }
                let factory = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0, RemoteMapping.defaults[input, $0]) })
                guard button.actions == factory else { return button }
                var migrated = button
                migrated.actions[.double] = nil
                migrated.actions[.long] = nil
                return migrated
            }
        }
    }

    func effectiveMapping(_ mapping: RemoteMapping, for profile: JoyConProfile) -> RemoteMapping {
        var result = mapping
        for button in globalButtons[profile.id] ?? [] {
            guard let input = button.input else { continue }
            for (gesture, action) in button.actions { result[input, gesture] = action }
        }
        if let voice = voiceButtons[profile.id], let input = voice.input {
            result[input] = .init(action: .voiceShortcut, voiceShortcut: voice.shortcut)
            result[input, .double] = .init()
            result[input, .long] = .init()
        }
        return result
    }

    var globalButtonCount: Int {
        globalButtons.values.flatMap { $0 }.compactMap(\.input).count
            + voiceButtons.values.compactMap(\.input).count
    }
}
