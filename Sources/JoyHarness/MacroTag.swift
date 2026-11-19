import Foundation

struct MacroTag: Identifiable, Equatable {
    let id: String
    let name: String

    static let general = Self(id: "general", name: "通用")
    static let all = [general] + HarnessApplication.defaults.map { Self(id: $0.id, name: $0.name) }
}

extension Configuration {
    func addingBuiltInMacros() -> Self {
        var result = self
        result.macros = DefaultMacros.addingMissing(to: macros, since: macroPresetsVersion ?? 0)
        result.macroPresetsVersion = max(macroPresetsVersion ?? 0, DefaultMacros.version)
        return result
    }
}
