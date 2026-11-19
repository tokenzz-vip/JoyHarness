import SwiftUI

struct PendingPhraseDeletion: Identifiable {
    let id = UUID()
    let phraseID: UUID
    let name: String
    let assignments: [ControllerInput]
}

struct DeletedPhrase: Identifiable {
    let phrase: SavedPhrase
    let assignments: [ControllerInput]
    let index: Int
    let previous: UUID?
    let next: UUID?
    var id: UUID { phrase.id }

    func insertionIndex(in ids: [UUID]) -> Int {
        if let next, let index = ids.firstIndex(of: next) { return index }
        if let previous, let index = ids.firstIndex(of: previous) { return index + 1 }
        return min(index, ids.count)
    }
}

extension DashboardModel {
    /// Binding priority affects presentation without replacing the user's manual order.
    var boundPhrases: [SavedPhrase] {
        let byID = Dictionary(configuration.phrases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var included = Set<UUID>()
        return PhraseAssignments.inputs.compactMap { input in
            guard let id = configuration.phraseAssignments[input], included.insert(id).inserted else { return nil }
            return byID[id]
        }
    }

    var unboundPhrases: [SavedPhrase] {
        let boundIDs = Set(PhraseAssignments.inputs.compactMap { configuration.phraseAssignments[$0] })
        return configuration.phrases.filter { !boundIDs.contains($0.id) }
    }

    var orderedPhrases: [SavedPhrase] { boundPhrases + unboundPhrases }

    func moveUnboundPhrases(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let boundIDs = Set(PhraseAssignments.inputs.compactMap { configuration.phraseAssignments[$0] })
        let indices = configuration.phrases.indices.filter { !boundIDs.contains(configuration.phrases[$0].id) }
        guard !offsets.isEmpty, offsets.allSatisfy({ indices.indices.contains($0) }),
              (0...indices.count).contains(destination) else { return }
        var reordered = indices.map { configuration.phrases[$0] }
        reordered.move(fromOffsets: offsets, toOffset: destination)
        var updated = configuration.phrases
        for (index, phrase) in zip(indices, reordered) { updated[index] = phrase }
        if updated != configuration.phrases { configuration.phrases = updated }
    }

    func requestPhraseDeletion(_ id: UUID) {
        pendingPhraseDeletion = nil
        guard let phrase = configuration.phrases.first(where: { $0.id == id }) else { return }
        let assignments = PhraseAssignments.inputs.filter { configuration.phraseAssignments[$0] == id }
        if assignments.isEmpty {
            deletePhrase(id)
        } else {
            pendingPhraseDeletion = PendingPhraseDeletion(phraseID: id, name: phrase.displayTitle, assignments: assignments)
        }
    }

    func confirmPhraseDeletion(_ id: UUID) {
        guard let pending = pendingPhraseDeletion, pending.id == id else { return }
        guard let phrase = configuration.phrases.first(where: { $0.id == pending.phraseID }) else {
            pendingPhraseDeletion = nil
            message = "该常用语已删除，请重新选择。"
            return
        }
        let assignments = PhraseAssignments.inputs.filter { configuration.phraseAssignments[$0] == phrase.id }
        guard phrase.displayTitle == pending.name, assignments == pending.assignments else {
            pendingPhraseDeletion = PendingPhraseDeletion(phraseID: phrase.id, name: phrase.displayTitle, assignments: assignments)
            message = "引用或名称已变化，请核对最新删除影响后再确认。"
            return
        }
        deletePhrase(phrase.id)
        pendingPhraseDeletion = nil
    }

    private func deletePhrase(_ id: UUID) {
        guard let index = configuration.phrases.firstIndex(where: { $0.id == id }) else { return }
        let phrases = configuration.phrases
        let slots = PhraseAssignments.inputs.filter { configuration.phraseAssignments[$0] == id }
        let deleted = DeletedPhrase(phrase: phrases[index], assignments: slots, index: index,
                                    previous: index > 0 ? phrases[index - 1].id : nil,
                                    next: index + 1 < phrases.count ? phrases[index + 1].id : nil)
        var updated = configuration
        updated.phrases.remove(at: index)
        for input in slots { updated.phraseAssignments[input] = nil }
        configuration = updated
        phraseDeletionUndoStack.append(deleted)
    }

    func undoPhraseDeletion() {
        guard let deleted = phraseDeletionUndoStack.last else { return }
        guard !configuration.phrases.contains(where: { $0.id == deleted.id }) else {
            message = "无法撤销：已有相同 ID 的常用语。"; return
        }
        guard configuration.phrases.count < 500 else {
            message = "无法撤销：常用语库已达 500 条上限。"; return
        }
        guard deleted.assignments.allSatisfy({ configuration.phraseAssignments[$0] == nil }) else {
            message = "无法撤销：原五向位置已重新分配，请先解除新分配后重试。"; return
        }
        var updated = configuration
        updated.phrases.insert(deleted.phrase, at: deleted.insertionIndex(in: updated.phrases.map(\.id)))
        for input in deleted.assignments { updated.phraseAssignments[input] = deleted.id }
        configuration = updated
        phraseDeletionUndoStack.removeLast()
        message = "已撤销删除「\(deleted.phrase.displayTitle)」"
    }
}
