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
import VLogging

/// Drives the word highlight from the audio player's own clock.
///
/// It polls the position within the sura file that is currently playing and asks the
/// sura's timeline which word covers that instant, which keeps pause, resume, seek,
/// repeat and rate changes correct for free — the clock is the source of truth rather
/// than a timer started at an ayah boundary. A poll costs one binary search, so the
/// interval is set by how tight the highlight should track the voice, not by cost.
///
/// Word timings live in the reciter's own timing database, the one the app already
/// downloads and unzips for every gapless reciter. A reciter whose database carries no
/// word segments simply never highlights anything, so no reciter is named here.
@MainActor
final class RecitationWordFollower {
    // MARK: Lifecycle

    init(
        databaseURL: @escaping (Reciter) -> URL? = { $0.localDatabasePath?.url },
        currentTime: @escaping @MainActor () -> TimeInterval?
    ) {
        self.databaseURL = databaseURL
        self.currentTime = currentTime
    }

    // MARK: Internal

    /// Called with the word under the playhead, only when it changes.
    var onWordChanged: (@MainActor (Word?) -> Void)?

    /// The in-flight load of the current sura's timings, so callers can await it.
    private(set) var loadTask: Task<Void, Never>?

    /// Called at every ayah boundary. Loads that sura's timings and starts polling.
    ///
    /// Gapped reciters have no timing database at all, so they can never be followed.
    func playing(ayah: AyahNumber, reciter: Reciter?) {
        guard let reciter, let url = databaseURL(reciter) else {
            stop()
            return
        }
        if url != currentDatabaseURL {
            // A different reciter: everything loaded for the previous one is now stale.
            currentDatabaseURL = url
            persistence = WordSegmentPersistence(fileURL: url)
            loadedSura = nil
            timeline = .empty
        }
        let sura = ayah.sura.suraNumber
        let isNewSura = loadedSura != sura
        quran = ayah.quran
        load(sura: sura)
        // This runs at every ayah boundary. Poll optimistically while a new sura's
        // timings load, but once they are known to be empty, leave the loop stopped
        // rather than restarting it on each of that sura's ayahs.
        if isNewSura || !timeline.isEmpty {
            startPolling()
        }
    }

    func stop() {
        pause()
        loadTask?.cancel()
        loadTask = nil
        loadedSura = nil
        timeline = .empty
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

    /// Reads the playhead once and emits the word under it, if it changed.
    ///
    /// The poll loop is only a repeated call to this, so tests drive it directly rather
    /// than waiting on wall-clock sleeps.
    func tick() {
        guard let quran, let seconds = currentTime(), !timeline.isEmpty else {
            return
        }
        let millis = Int(seconds * 1000)
        guard let segment = timeline.segment(atMillis: millis),
              let verse = AyahNumber(quran: quran, sura: segment.sura, ayah: segment.ayah)
        else {
            // A gap between words, or an ayah the upstream data does not cover.
            // Hold the last highlight rather than flickering it off.
            return
        }
        emit(Word(verse: verse, wordNumber: segment.position))
    }

    // MARK: Private

    // `Duration` would read better but needs iOS 16, above this package's minimum.
    private static let pollIntervalNanoseconds: UInt64 = 30 * NSEC_PER_MSEC

    private let databaseURL: (Reciter) -> URL?
    private let currentTime: @MainActor () -> TimeInterval?

    private var persistence: WordSegmentPersistence?
    private var currentDatabaseURL: URL?
    private var quran: Quran?
    private var loadedSura: Int?
    private var timeline: WordSegmentTimeline = .empty
    private var pollTask: Task<Void, Never>?
    private var lastWord: Word?

    private func load(sura: Int) {
        guard loadedSura != sura, let persistence else {
            return
        }
        loadedSura = sura
        timeline = .empty
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let loaded: WordSegmentTimeline
            do {
                loaded = try await persistence.timeline(forSura: sura)
            } catch {
                logger.error("WordFollower: couldn't load word segments for sura \(sura): \(error)")
                // Clear the marker so the next ayah boundary retries. A transient failure
                // — a busy database at startup — must not disable the sura for good.
                self?.loadedSura = nil
                return
            }
            guard !Task.isCancelled, let self, loadedSura == sura else {
                return
            }
            timeline = loaded
            if loaded.isEmpty {
                // Most suras have no word timings. Stop polling rather than waking the
                // main actor 33 times a second to look at an empty timeline.
                logger.info("WordFollower: no word segments for sura \(sura); not following")
                pause()
            } else {
                logger.info("WordFollower: loaded \(loaded.segments.count) word segments for sura \(sura)")
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else {
            return
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Stopping when the follower is gone is what ends this loop if the
                // banner is torn down without a stop() — nothing else cancels it.
                guard let self else {
                    return
                }
                tick()
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            }
        }
    }

    private func emit(_ word: Word?) {
        guard word != lastWord else {
            return
        }
        lastWord = word
        onWordChanged?(word)
    }
}
