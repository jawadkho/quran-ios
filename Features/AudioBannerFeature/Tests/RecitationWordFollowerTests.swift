//
//  RecitationWordFollowerTests.swift
//
//
//  Created by Jawad Khokhar on 2026-08-28.
//

import AudioTimingPersistence
import Foundation
import QuranAudio
import QuranKit
import XCTest
@testable import AudioBannerFeature

@MainActor
final class RecitationWordFollowerTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        playhead = nil
        emitted = []
    }

    // MARK: - Reciter support

    func testSupportsTheReciterWhoseTimingsShip() {
        XCTAssertTrue(RecitationWordFollower.supports(husary))
    }

    func testDoesNotSupportOtherGaplessReciters() {
        XCTAssertFalse(RecitationWordFollower.supports(reciter(audioType: .gapless(databaseName: "minshawi"))))
    }

    func testDoesNotSupportGappedReciters() {
        XCTAssertFalse(RecitationWordFollower.supports(reciter(audioType: .gapped)))
    }

    // MARK: - Following

    func testHighlightsTheWordUnderThePlayhead() async {
        let follower = await startedFollower()

        playhead = 1.2
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1)])
    }

    func testMovesToTheNextWordAsPlaybackAdvances() async {
        let follower = await startedFollower()

        playhead = 1.2
        follower.tick()
        playhead = 1.6
        follower.tick()
        playhead = 3.1
        follower.tick()

        XCTAssertEqual(emitted, [
            word(ayah: 1, position: 1),
            word(ayah: 1, position: 2),
            word(ayah: 2, position: 1),
        ])
    }

    /// Polling runs ~33 times a second, so repeats must not reach the UI.
    func testReportsAWordOnlyOnceWhileItIsStillBeingRecited() async {
        let follower = await startedFollower()

        playhead = 1.0
        follower.tick()
        playhead = 1.2
        follower.tick()
        playhead = 1.4999
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1)])
    }

    /// Silence between words should hold the highlight rather than flicker it off.
    func testKeepsTheLastWordThroughTheSilenceBetweenWords() async {
        let follower = await startedFollower()

        playhead = 1.6
        follower.tick()
        playhead = 2.2 // the 2000-2500ms gap
        follower.tick()
        playhead = 2.7
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 2), word(ayah: 1, position: 3)])
    }

    func testEmitsNothingBeforeTheFirstWordStarts() async {
        let follower = await startedFollower()

        playhead = 0.1
        follower.tick()

        XCTAssertEqual(emitted, [])
    }

    func testEmitsNothingWhileThePlayheadIsUnknown() async {
        let follower = await startedFollower()

        playhead = nil
        follower.tick()

        XCTAssertEqual(emitted, [])
    }

    // MARK: - Gating

    func testUnsupportedReciterClearsTheHighlightAndFollowsNothing() async {
        let follower = await startedFollower()
        playhead = 1.2
        follower.tick()
        XCTAssertEqual(emitted, [word(ayah: 1, position: 1)])

        follower.playing(ayah: ayah(1), reciter: reciter(audioType: .gapped))
        await follower.loadTask?.value
        playhead = 1.6
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1), nil], "should clear, then stay silent")
    }

    func testNoReciterClearsTheHighlight() async {
        let follower = await startedFollower()
        playhead = 1.2
        follower.tick()

        follower.playing(ayah: ayah(1), reciter: nil)

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1), nil])
    }

    // MARK: - Lifecycle

    func testStoppingClearsTheHighlightAndTheLoadedTimings() async {
        let follower = await startedFollower()
        playhead = 1.2
        follower.tick()

        follower.stop()
        playhead = 1.6
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1), nil], "no word survives a stop")
    }

    func testStoppingTwiceClearsOnlyOnce() async {
        let follower = await startedFollower()
        playhead = 1.2
        follower.tick()

        follower.stop()
        follower.stop()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1), nil])
    }

    /// Pausing keeps the loaded sura so resuming does not wait for the next ayah.
    func testPausingKeepsTheHighlightAndTheTimings() async {
        let follower = await startedFollower()
        playhead = 1.2
        follower.tick()

        follower.pause()
        follower.resume()
        playhead = 1.6
        follower.tick()

        XCTAssertEqual(emitted, [word(ayah: 1, position: 1), word(ayah: 1, position: 2)])
    }

    func testSuraWithoutTimingsHighlightsNothing() async {
        let follower = makeFollower()
        // Sura 3 is absent from the fixture, as most suras are from the shipped timings.
        follower.playing(ayah: ayah(1, sura: 3), reciter: husary)
        await follower.loadTask?.value
        follower.pause()

        playhead = 1.2
        follower.tick()

        XCTAssertEqual(emitted, [])
    }

    // MARK: Private

    private let quran = Quran.hafsMadani1405
    private var playhead: TimeInterval?
    private var emitted: [Word?] = []

    private var husary: Reciter {
        reciter(audioType: .gapless(databaseName: "husary"))
    }

    private func makeFollower() -> RecitationWordFollower {
        let follower = RecitationWordFollower(
            persistence: WordSegmentPersistence(fileURL: Bundle.module.url(forResource: "word_segments", withExtension: "db")!),
            currentTime: { [weak self] in self?.playhead }
        )
        follower.onWordChanged = { [weak self] word in self?.emitted.append(word) }
        return follower
    }

    /// A follower already following sura 1, with its timings loaded.
    ///
    /// Paused so the wall-clock poll loop cannot interleave with the `tick()` calls the
    /// tests make; pausing keeps the loaded timings, which is exactly what is wanted here.
    private func startedFollower() async -> RecitationWordFollower {
        let follower = makeFollower()
        follower.playing(ayah: ayah(1), reciter: husary)
        await follower.loadTask?.value
        follower.pause()
        return follower
    }

    private func reciter(audioType: AudioType) -> Reciter {
        Reciter(
            id: 1,
            nameKey: "reciter",
            directory: "reciter",
            audioURL: URL(string: "https://example.com/audio/")!,
            audioType: audioType,
            hasGaplessAlternative: false,
            category: .arabic
        )
    }

    private func ayah(_ ayah: Int, sura: Int = 1) -> AyahNumber {
        AyahNumber(quran: quran, sura: sura, ayah: ayah)!
    }

    private func word(ayah number: Int, position: Int, sura: Int = 1) -> Word {
        Word(verse: ayah(number, sura: sura), wordNumber: position)
    }
}
