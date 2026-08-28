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

    /// Half-open, so a word ends exactly where the next one starts.
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

    /// A sura's word spans. Suras the timings do not cover return an empty timeline.
    public func timeline(forSura sura: Int) async throws -> WordSegmentTimeline {
        let segments = try await db.read { db in
            try GRDBWordSegment
                .filter(GRDBWordSegment.Columns.sura == sura)
                .order(GRDBWordSegment.Columns.startMs)
                .fetchAll(db)
                .map(WordSegment.init)
        }
        return WordSegmentTimeline(segments: segments)
    }

    // MARK: Internal

    let db: DatabaseConnection
}

private struct GRDBWordSegment: Decodable, FetchableRecord, TableRecord {
    enum CodingKeys: String, CodingKey {
        case sura
        case ayah
        case position
        case startMs = "start_ms"
        case endMs = "end_ms"
    }

    enum Columns {
        static let sura = Column(CodingKeys.sura)
        static let startMs = Column(CodingKeys.startMs)
    }

    static var databaseTableName: String {
        "word_segments"
    }

    var sura: Int
    var ayah: Int
    var position: Int
    var startMs: Int
    var endMs: Int
}

private extension WordSegment {
    init(_ record: GRDBWordSegment) {
        self.init(
            sura: record.sura,
            ayah: record.ayah,
            position: record.position,
            startMs: record.startMs,
            endMs: record.endMs
        )
    }
}
