import AppKit
import SwiftUI
import XCTest
@testable import JoyHarness

@MainActor
final class PhraseEditingTests: XCTestCase {
    private func withModel(_ body: (DashboardModel, UserDefaults) throws -> Void) rethrows {
        let suite = "JoyHarness.PhraseEditingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel(defaults: defaults, preview: true)
        model.configuration.phraseAssignments = PhraseAssignments()
        try body(model, defaults)
    }

    func testBoundOrderingDeduplicatesRowsAndPreservesManualOrder() {
        withModel { model, _ in
            let entries = (0..<7).map { SavedPhrase(title: "条目\($0)", text: "内容\($0)") }
            model.configuration.phrases = entries
            for (input, index) in zip(PhraseAssignments.inputs, [6, 3, 4, 2, 0]) {
                model.configuration.phraseAssignments[input] = entries[index].id
            }
            XCTAssertEqual(model.orderedPhrases.map(\.id), [6, 3, 4, 2, 0, 1, 5].map { entries[$0].id })
            model.configuration.phraseAssignments[.down] = entries[6].id
            XCTAssertEqual(model.orderedPhrases.map(\.id), [6, 4, 2, 0, 1, 3, 5].map { entries[$0].id })
            XCTAssertEqual(model.configuration.phrases, entries)
        }
    }

    func testUnboundDragKeepsAssignmentsAndPersistsAcrossRestart() {
        withModel { model, defaults in
            let entries = (0..<5).map { SavedPhrase(title: "条目\($0)", text: "内容\($0)") }
            model.configuration.phrases = entries
            model.configuration.phraseAssignments[.up] = entries[1].id
            model.configuration.phraseAssignments[.a] = entries[3].id
            let slots = model.configuration.phraseAssignments
            model.moveUnboundPhrases(fromOffsets: IndexSet(integer: 0), toOffset: 3)
            XCTAssertEqual(model.configuration.phrases.map(\.id), [2, 1, 4, 3, 0].map { entries[$0].id })
            XCTAssertEqual(model.orderedPhrases.map(\.id), [1, 3, 2, 4, 0].map { entries[$0].id })
            XCTAssertEqual(model.configuration.phraseAssignments, slots)
            let restored = DashboardModel(defaults: defaults, preview: true)
            XCTAssertEqual(restored.orderedPhrases, model.orderedPhrases)
            restored.moveUnboundPhrases(fromOffsets: IndexSet(integer: 2), toOffset: 0)
            restored.configuration.phraseAssignments = PhraseAssignments()
            XCTAssertEqual(restored.orderedPhrases, entries)
        }
    }

    func testReferencedDeleteRequiresReviewAndUndoRestoresAllSlotsAndOrder() throws {
        try withModel { model, _ in
            let entries = Array(DefaultPhrases.all.prefix(3))
            model.configuration.phrases = entries
            model.configuration.phraseAssignments[.up] = entries[1].id
            model.configuration.phraseAssignments[.a] = entries[1].id
            model.requestPhraseDeletion(entries[1].id)
            let pending = try XCTUnwrap(model.pendingPhraseDeletion)
            XCTAssertEqual(pending.assignments, [.up, .a])
            XCTAssertEqual(model.configuration.phrases, entries)
            model.confirmPhraseDeletion(pending.id)
            XCTAssertNil(model.pendingPhraseDeletion)
            XCTAssertNil(model.configuration.phraseAssignments[.up])
            XCTAssertNil(model.configuration.phraseAssignments[.a])
            XCTAssertEqual(model.configuration.phrases, [entries[0], entries[2]])
            model.undoPhraseDeletion()
            XCTAssertEqual(model.configuration.phrases, entries)
            XCTAssertEqual(model.configuration.phraseAssignments[.up], entries[1].id)
            XCTAssertEqual(model.configuration.phraseAssignments[.a], entries[1].id)
        }
    }

    func testUndoDoesNotOverwriteReassignedSlotAndCanRetry() throws {
        try withModel { model, _ in
            let entries = Array(DefaultPhrases.all.prefix(3))
            model.configuration.phrases = entries
            model.configuration.phraseAssignments[.up] = entries[1].id
            model.requestPhraseDeletion(entries[1].id)
            model.confirmPhraseDeletion(try XCTUnwrap(model.pendingPhraseDeletion).id)
            model.configuration.phraseAssignments[.up] = entries[0].id
            let before = model.configuration
            model.undoPhraseDeletion()
            XCTAssertEqual(model.configuration, before)
            XCTAssertEqual(model.phraseDeletionUndoStack.count, 1)
            model.configuration.phraseAssignments[.up] = nil
            model.undoPhraseDeletion()
            XCTAssertEqual(model.configuration.phrases, entries)
            XCTAssertTrue(model.phraseDeletionUndoStack.isEmpty)
        }
    }

    func testUnboundDeletesCanBeUndoneInSequence() {
        withModel { model, _ in
            let entries = Array(DefaultPhrases.all.prefix(4))
            model.configuration.phrases = entries
            model.requestPhraseDeletion(entries[1].id)
            model.requestPhraseDeletion(entries[2].id)
            XCTAssertNil(model.pendingPhraseDeletion)
            model.undoPhraseDeletion()
            model.undoPhraseDeletion()
            XCTAssertEqual(model.configuration.phrases, entries)
        }
    }

    func testChangedAssignmentsRequireFreshReview() throws {
        try withModel { model, _ in
            let phrase = DefaultPhrases.all[0]
            model.configuration.phrases = [phrase]
            model.configuration.phraseAssignments[.up] = phrase.id
            model.requestPhraseDeletion(phrase.id)
            let original = try XCTUnwrap(model.pendingPhraseDeletion)
            model.configuration.phraseAssignments[.a] = phrase.id
            model.confirmPhraseDeletion(original.id)
            let revised = try XCTUnwrap(model.pendingPhraseDeletion)
            XCTAssertNotEqual(original.id, revised.id)
            XCTAssertEqual(revised.assignments, [.up, .a])
            XCTAssertEqual(model.configuration.phrases, [phrase])
            model.confirmPhraseDeletion(revised.id)
            XCTAssertTrue(model.configuration.phrases.isEmpty)
        }
    }
}
