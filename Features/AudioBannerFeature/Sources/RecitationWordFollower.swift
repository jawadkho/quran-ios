//
//  RecitationWordFollower.swift
//
//
//  Moves the word pointer along with the reciter's voice.
//

import AudioTimingPersistence
import Foundation
import QuranAudio
import QuranKit
import QuranResources
import VLogging

/// Drives the word highlight from the audio player's own clock.
///
/// It polls the position within the sura file that is currently playing and asks the
/// segments table which word covers that instant, which keeps pause, resume, seek,
/// repeat and rate changes correct for free — the clock is the source of truth rather
/// than a timer started at an ayah boundary.
///
/// Only Al-Husary has word timings today, so every other reciter is a no-op.
@MainActor
final class RecitationWordFollower {
    // MARK: Lifecycle

    init(currentTime: @escaping @MainActor () -> TimeInterval?) {
        self.currentTime = currentTime
    }

    // MARK: Internal

    /// Called with the word under the playhead, only when it changes.
    var onWordChanged: (@MainActor (Word?) -> Void)?

    static func supports(_ reciter: Reciter) -> Bool {
        reciter.audioType == .gapless(databaseName: Self.supportedDatabaseName)
    }

    /// Called at every ayah boundary. Loads that sura's timings and starts polling.
    func playing(ayah: AyahNumber, reciter: Reciter?) {
        guard let reciter, Self.supports(reciter) else {
            stop()
            return
        }
        quran = ayah.quran
        load(sura: ayah.sura.suraNumber)
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        loadTask?.cancel()
        loadTask = nil
        loadedSura = nil
        segments = []
        emit(nil)
    }

    /// Keeps the loaded timings but stops moving the highlight.
    func pause() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Resumes after a pause, without waiting for the next ayah boundary.
    func resume() {
        guard loadedSura != nil else {
            return
        }
        startPolling()
    }

    // MARK: Private

    private static let supportedDatabaseName = "husary"
    private static let pollIntervalNanoseconds: UInt64 = 30 * NSEC_PER_MSEC

    private let currentTime: @MainActor () -> TimeInterval?
    private lazy var persistence = WordSegmentPersistence(fileURL: QuranResources.husaryWordSegmentsDatabase)

    private var quran: Quran?
    private var loadedSura: Int?
    private var segments: [WordSegment] = []
    private var loadTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastWord: Word?

    private func load(sura: Int) {
        guard loadedSura != sura else {
            return
        }
        loadedSura = sura
        segments = []
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let persistence = self?.persistence else {
                return
            }
            let loaded = (try? await persistence.segments(forSura: sura)) ?? []
            guard !Task.isCancelled, let self, loadedSura == sura else {
                return
            }
            segments = loaded
            logger.info("WordFollower: loaded \(loaded.count) word segments for sura \(sura)")
        }
    }

    private func startPolling() {
        guard pollTask == nil else {
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            }
        }
    }

    private func tick() {
        guard let quran, let seconds = currentTime(), !segments.isEmpty else {
            return
        }
        let millis = Int(seconds * 1000)
        guard let segment = segment(at: millis),
              let verse = AyahNumber(quran: quran, sura: segment.sura, ayah: segment.ayah)
        else {
            // A gap between words, or an ayah the upstream data does not cover.
            // Hold the last highlight rather than flickering it off.
            return
        }
        emit(Word(verse: verse, wordNumber: segment.position))
    }

    /// Spans never overlap, so a binary search on start time finds the only candidate.
    private func segment(at millis: Int) -> WordSegment? {
        var low = 0
        var high = segments.count - 1
        var candidate: WordSegment?
        while low <= high {
            let mid = (low + high) / 2
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

    private func emit(_ word: Word?) {
        guard word != lastWord else {
            return
        }
        lastWord = word
        onWordChanged?(word)
    }
}
