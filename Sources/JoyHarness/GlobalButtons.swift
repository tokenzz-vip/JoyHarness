import Foundation

struct GlobalButton: Codable, Equatable, Identifiable {
    var id = UUID()
    var input: ControllerInput?
    var actions: [Gesture: ButtonMapping] = [:]
}

extension JoyConProfile {
    var physicalInputs: [ControllerInput] {
        ControllerInput.allCases.filter {
            $0.side == side && !$0.isStickDirection && $0 != .gl && $0 != .gr
                && (generation == .second || !$0.secondGenerationOnly)
        }
    }
}

extension Configuration {
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
        return result
    }
}
