//
//  GRDBWordSegmentPersistence.swift
//
//
//  Word-by-word recitation timings, keyed by the sura audio file's own timeline.
//

import Foundation
import GRDB
import SQLitePersistence

/// A single word's span within a sura's audio file.
///
/// A word may have more than one span when the reciter repeats or elongates a
/// passage, so spans are looked up by time range rather than by position.
public struct WordSegment: Sendable, Hashable {
    // MARK: Lifecycle

    public init(sura: Int, ayah: Int, position: Int, startMs: Int, endMs: Int) {
        self.sura = sura
        self.ayah = ayah
        self.position = position
        self.startMs = startMs
        self.endMs = endMs
    }

    // MARK: Public

    public let sura: Int
    public let ayah: Int
    /// The glyph position used by `Word.wordNumber`, not the plain word index.
    public let position: Int
    public let startMs: Int
    public let endMs: Int

    public func contains(millis: Int) -> Bool {
        millis >= startMs && millis < endMs
    }
}

public struct WordSegmentPersistence {
    // MARK: Lifecycle

    public init(fileURL: URL) {
        db = DatabaseConnection(url: fileURL)
    }

    // MARK: Public

    /// All spans for a sura, ordered by start time. Suras with no timings return an empty array.
    public func segments(forSura sura: Int) async throws -> [WordSegment] {
        try await db.read { db in
            try GRDBWordSegment
                .filter(GRDBWordSegment.Columns.sura == sura)
                .order(GRDBWordSegment.Columns.startMs)
                .fetchAll(db)
                .map {
                    WordSegment(sura: $0.sura, ayah: $0.ayah, position: $0.position, startMs: $0.start_ms, endMs: $0.end_ms)
                }
        }
    }

    // MARK: Internal

    let db: DatabaseConnection
}

private struct GRDBWordSegment: Decodable, FetchableRecord, TableRecord {
    enum Columns {
        static let sura = Column(CodingKeys.sura)
        static let ayah = Column(CodingKeys.ayah)
        static let position = Column(CodingKeys.position)
        static let startMs = Column(CodingKeys.start_ms)
    }

    static var databaseTableName: String {
        "word_segments"
    }

    var sura: Int
    var ayah: Int
    var position: Int
    var start_ms: Int
    var end_ms: Int
}
