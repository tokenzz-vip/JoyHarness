import Foundation

enum MacroExecutionError: LocalizedError {
    case circularReference, missingReference, tooManySteps, unsupportedAction
    var errorDescription: String? {
        switch self {
        case .circularReference: "组合动作存在循环引用，请修改后重试。"
        case .missingReference: "组合动作中的引用未设置或已删除，请重新选择。"
        case .tooManySteps: "组合动作展开后超过 100 个步骤，请减少步骤或嵌套调用。"
        case .unsupportedAction: "组合动作不支持暂停或恢复映射、切换摇杆模式、唤出常用语，请移除该步骤后重试。"
        }
    }
}

/// Expand a snapshot before scheduling so nested calls never restart the runner.
struct MacroExecutionPlan {
    struct Event: Equatable {
        let mapping: ButtonMapping
        let offset: TimeInterval
    }
    let events: [Event]
    let duration: TimeInterval

    init(_ macro: ActionMacro, macros: [ActionMacro]) throws {
        let byID = Dictionary(macros.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var events: [Event] = [], offset: TimeInterval = 0, remainingSteps = 100
        func expand(_ macro: ActionMacro, path: Set<UUID>) throws {
            guard !path.contains(macro.id) else { throw MacroExecutionError.circularReference }
            let path = path.union([macro.id])
            for step in macro.steps {
                guard remainingSteps > 0 else { throw MacroExecutionError.tooManySteps }
                remainingSteps -= 1
                guard step.mapping.action.canRunInMacro else { throw MacroExecutionError.unsupportedAction }
                if step.mapping.action == .macro {
                    guard let id = step.mapping.macroID, let child = byID[id] else { throw MacroExecutionError.missingReference }
                    try expand(child, path: path)
                } else {
                    events.append(.init(mapping: step.mapping, offset: offset))
                }
                offset += max(0, min(30, step.delay.isFinite ? step.delay : 0))
            }
        }
        try expand(macro, path: [])
        self.events = events; duration = offset
    }

    static func wouldCreateCycle(referencing childID: UUID, from parentID: UUID, macros: [ActionMacro]) -> Bool {
        let byID = Dictionary(macros.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pending = [childID], visited: Set<UUID> = []
        while let id = pending.popLast() {
            if id == parentID { return true }
            guard visited.insert(id).inserted, let macro = byID[id] else { continue }
            pending.append(contentsOf: macro.steps.compactMap { $0.mapping.action == .macro ? $0.mapping.macroID : nil })
        }
        return false
    }
}
