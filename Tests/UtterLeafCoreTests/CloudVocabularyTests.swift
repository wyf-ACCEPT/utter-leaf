import XCTest
@testable import UtterLeafCore

final class CloudVocabularyTests: XCTestCase {
    func testDeletionWinsOverAnOfflineEditAndDoesNotRetainTerm() {
        var original = CloudVocabularyRow(entry: .init(term: "SyntheticTerm"), source: UUID().uuidString, updated: 10)
        var deleted = original; deleted.deleted = true; deleted.entry = nil; deleted.updated = 20
        original.updated = 30
        var a = CloudVocabularyCache(), b = CloudVocabularyCache()
        [original, deleted].forEach { a.merge($0) }; [deleted, original].forEach { b.merge($0) }
        XCTAssertTrue(a.entries.isEmpty); XCTAssertTrue(b.entries.isEmpty)
        XCTAssertNil(a.rows[original.id]?.entry)
        XCTAssertFalse(String(data: try! JSONEncoder().encode(a.rows), encoding: .utf8)!.contains("SyntheticTerm"))
    }
    func testOfflineSameSpellingAddsAndConcurrentEnableEditsConverge() {
        let first = CloudVocabularyRow(entry: .init(term: "SyntheticTerm"), source: UUID().uuidString, updated: 10)
        let second = CloudVocabularyRow(entry: .init(term: "syntheticterm", enabled: false), source: UUID().uuidString, updated: 20)
        var a = CloudVocabularyCache(), b = CloudVocabularyCache()
        [first, second].forEach { a.merge($0) }; [second, first].forEach { b.merge($0) }
        XCTAssertEqual(a.entries, b.entries); XCTAssertEqual(a.entries.count, 1); XCTAssertFalse(a.entries[0].enabled)
        var bad = first; bad.entry?.term = String(repeating: "a", count: 101); a.merge(bad)
        XCTAssertEqual(a.entries.count, 1)
    }
    @MainActor func testMigrationOfflineEditsAndTombstonesSurviveRestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("vocabulary.json")
        let sync = CloudVocabularySync(file: file), word = VocabularyEntry(term: "SyntheticTerm", aliases: ["SyntheticAlias"])
        sync.seed([word]); try sync.delete(word.id)
        let restored = CloudVocabularySync(file: file); restored.seed([word])
        XCTAssertTrue(restored.entries.isEmpty)
        XCTAssertThrowsError(try restored.upsert(word))
        let newWord = VocabularyEntry(term: "SyntheticNew")
        try restored.upsert(newWord)
        XCTAssertEqual(CloudVocabularySync(file: file).entries, [newWord])
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: restored.diagnostic), encoding: .utf8)!.contains("Synthetic"))
    }
}
