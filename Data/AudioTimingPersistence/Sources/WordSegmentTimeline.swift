//
//  WordSegmentTimeline.swift
//
//
//  The word spans of one sura, ready for playhead lookups.
//

import Foundation

/// One sura's word spans, ordered by start time, queried by playback position.
///
/// Kept separate from the persistence that loads it so the lookup — the part with the
/// interesting edge cases — can be exercised without a database or a running player.
public struct WordSegmentTimeline: Sendable, Equatable {
    // MARK: Lifecycle

    public init(segments: [WordSegment]) {
        self.segments = segments.sorted { $0.startMs < $1.startMs }
    }

    // MARK: Public

    public static let empty = WordSegmentTimeline(segments: [])

    /// The spans, ordered by start time.
    public let segments: [WordSegment]

    public var isEmpty: Bool {
        segments.isEmpty
    }

    /// The span covering `millis`, or nil while the reciter is between two words.
    ///
    /// Spans never overlap, so the last span starting at or before `millis` is the only
    /// candidate; it still has to contain `millis` to count, which is what keeps silence
    /// between words from reporting the word that just ended.
    public func segment(atMillis millis: Int) -> WordSegment? {
        var low = 0
        var high = segments.count - 1
        var candidate: WordSegment?
        while low <= high {
            let mid = low + (high - low) / 2
            let segment = segments[mid]
            if segment.startMs <= millis {
                candidate = segment
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return candidate.flatMap { $0.contains(millis: millis) ? $0 : nil }
    }
}
