import Foundation

struct MacroTag: Codable, Identifiable, Equatable {
    let id: String
    let name: String

    static let general = Self(id: "general", name: "通用")
    static let all = [general] + HarnessApplication.defaults.map { Self(id: $0.id, name: $0.name) }

    static func validatedName(_ name: String, in catalog: [Self], excluding id: String? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MacroTagError.emptyName }
        if catalog.contains(where: {
            $0.id != id && $0.name.compare(trimmed, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
        }) {
            throw MacroTagError.duplicateName
        }
        return trimmed
    }

    static func validatedCustomTags(_ tags: [Self]) throws -> [Self] {
        var ids = Set(all.map(\.id))
        var catalog = all
        for tag in tags {
            guard !tag.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  tag.id != "codex", ids.insert(tag.id).inserted else {
                throw Configuration.ConfigurationError.invalid
            }
            let name = try validatedName(tag.name, in: catalog)
            catalog.append(.init(id: tag.id, name: name))
        }
        return Array(catalog.dropFirst(all.count))
    }
}

enum MacroTagError: LocalizedError {
    case emptyName, duplicateName, builtIn, missing

    var errorDescription: String? {
        switch self {
        case .emptyName: "请输入标签名称。"
        case .duplicateName: "已存在同名标签，请使用其他名称。"
        case .builtIn: "内置标签为只读。"
        case .missing: "此标签已删除。"
        }
    }
}

extension Configuration {
    var macroTags: [MacroTag] { MacroTag.all + customMacroTags }

    func addingBuiltInMacros() -> Self {
        var result = self
        let knownTags = Set(macroTags.map(\.id))
        result.macros = DefaultMacros.addingMissing(to: macros, since: macroPresetsVersion ?? 0, knownTags: knownTags)
        for index in result.macros.indices {
            result.macros[index].tagIDs.formIntersection(knownTags)
        }
        result.macroPresetsVersion = max(macroPresetsVersion ?? 0, DefaultMacros.version)
        return result
    }
}
