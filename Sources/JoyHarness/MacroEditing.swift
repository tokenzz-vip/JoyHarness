import Foundation

@MainActor
extension DashboardModel {
    var savedMacros: [ActionMacro] { configuration.macros }
    var customMacroTags: [MacroTag] { configuration.customMacroTags }
    var macroTags: [MacroTag] { configuration.macroTags }

    func saveCustomMacroTag(name: String, id: String? = nil) throws {
        let name = try MacroTag.validatedName(name, in: macroTags, excluding: id)
        var next = configuration
        if let id {
            let index = try customMacroTagIndex(id)
            next.customMacroTags[index] = .init(id: id, name: name)
        } else {
            next.customMacroTags.append(.init(id: UUID().uuidString, name: name))
        }
        try commitConfiguration(next)
    }

    func deleteCustomMacroTag(_ id: String) throws {
        let index = try customMacroTagIndex(id)
        var next = configuration
        next.customMacroTags.remove(at: index)
        for index in next.macros.indices {
            next.macros[index].tagIDs.remove(id)
        }
        try commitConfiguration(next)
    }

    private func customMacroTagIndex(_ id: String) throws -> Int {
        guard !MacroTag.all.contains(where: { $0.id == id }) else { throw MacroTagError.builtIn }
        guard let index = customMacroTags.firstIndex(where: { $0.id == id }) else { throw MacroTagError.missing }
        return index
    }

    var canAddMacro: Bool { configuration.customMacroCount < Configuration.customMacroLimit }

    @discardableResult
    func addMacro(tagIDs: Set<String> = [MacroTag.general.id]) -> UUID? {
        guard canAddMacro else {
            showNotice(.warning, "最多创建 \(Configuration.customMacroLimit) 个自定义组合动作。",
                       issue: .macroLimit, resolvedWhen: { $0.canAddMacro })
            return nil
        }
        var name = "新组合动作"
        var number = 2
        while configuration.macros.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }) {
            name = "新组合动作 \(number)"; number += 1
        }
        let macro = ActionMacro(name: name, tagIDs: tagIDs.intersection(macroTags.map(\.id)))
        configuration.macros.append(macro)
        return macro.id
    }

    func updateMacroTags(_ tags: Set<String>, for id: UUID) {
        guard let index = configuration.macros.firstIndex(where: { $0.id == id }) else { return }
        configuration.macros[index].tagIDs = tags.intersection(macroTags.map(\.id))
    }

    func macroNameError(_ name: String, excluding id: UUID) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "组合动作名称不能为空" }
        if configuration.macros.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "已存在同名组合动作，请使用其他名称"
        }
        return nil
    }

    @discardableResult
    func renameMacro(_ id: UUID, name: String) -> Bool {
        guard let index = configuration.macros.firstIndex(where: { $0.id == id }) else { return false }
        if let error = macroNameError(name, excluding: id) {
            showNotice(.warning, error, issue: .macroName(id), resolvedWhen: { model in
                !model.savedMacros.contains { $0.id == id } || model.macroNameError(name, excluding: id) == nil
            })
            return false
        }
        var next = configuration
        next.macros[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard saveConfiguration(next) else { return false }
        clearNotice(for: .macroName(id))
        return true
    }

    func canNestMacro(_ childID: UUID, in parentID: UUID) -> Bool {
        !MacroExecutionPlan.wouldCreateCycle(referencing: childID, from: parentID, macros: configuration.macros)
    }

    @discardableResult
    func updateMacroSteps(_ steps: [MacroStep], for id: UUID) -> Bool {
        guard let index = configuration.macros.firstIndex(where: { $0.id == id }) else { return false }
        for step in steps where step.mapping.action == .macro {
            if let child = step.mapping.macroID, !canNestMacro(child, in: id) {
                showNotice(.warning, "组合动作不能引用自身或形成循环引用", issue: .macroSteps(id),
                           resolvedWhen: { $0.canNestMacro(child, in: id) || !$0.savedMacros.contains { $0.id == id } })
                return false
            }
        }
        guard steps.count <= 100, steps.allSatisfy({ $0.mapping.isComplete && $0.delay.isFinite && (0...30).contains($0.delay) }) else { return false }
        var next = configuration
        next.macros[index].steps = steps
        do {
            for macro in next.macros { _ = try MacroExecutionPlan(macro, macros: next.macros) }
        } catch {
            showNotice(.warning, error.localizedDescription, issue: .macroSteps(id),
                       resolvedWhen: { !$0.savedMacros.contains { $0.id == id } })
            return false
        }
        guard saveConfiguration(next) else { return false }
        clearNotice(for: .macroSteps(id))
        return true
    }

    func deleteMacro(_ id: UUID) {
        var next = configuration
        next.macros.removeAll { $0.id == id }
        for index in next.profiles.indices {
            for (key, mapping) in next.profiles[index].mapping.buttons where mapping.macroID == id {
                next.profiles[index].mapping.buttons[key] = .init()
            }
        }
        next.globalButtons = next.globalButtons.mapValues { buttons in
            buttons.map { button in
                var updated = button
                updated.actions = button.actions.mapValues { $0.macroID == id ? .init() : $0 }
                return updated
            }
        }
        for index in next.macros.indices {
            for step in next.macros[index].steps.indices where next.macros[index].steps[step].mapping.macroID == id {
                next.macros[index].steps[step].mapping = .init()
            }
        }
        configuration = next
    }

    func requestMacroBinding(_ id: UUID) {
        guard configuration.macros.contains(where: { $0.id == id && !$0.steps.isEmpty }) else { return }
        page = .mapping
        macroBindingRequest = id
    }
}
