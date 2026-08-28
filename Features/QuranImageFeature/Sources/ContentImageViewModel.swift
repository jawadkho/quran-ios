//
//  ContentImageViewModel.swift
//
//
//  Created by Mohamed Afifi on 2024-02-10.
//

import AnnotationsService
import Combine
import Crashing
import ImageService
import NoorUI
import QuranAnnotations
import QuranGeometry
import QuranKit
import ReadingService
import SwiftUI
import VLogging

@MainActor
class ContentImageViewModel: ObservableObject {
    // MARK: Lifecycle

    init(reading: Reading, page: Page, imageDataService: ImageDataService, highlightsService: QuranHighlightsService) {
        self.page = page
        self.reading = reading
        self.imageDataService = imageDataService
        self.highlightsService = highlightsService
        highlights = highlightsService.highlights

        highlightsService.$highlights
            .sink { [weak self] in self?.highlights = $0 }
            .store(in: &cancellables)

        highlightsService.scrolling
            .sink { [weak self] in
                self?.scrollToVerseIfNeeded()
            }
            .store(in: &cancellables)
    }

    // MARK: Internal

    let page: Page
    @Published var imagePage: ImagePage?
    @Published var suraHeaderLocations: [SuraHeaderLocation] = []
    @Published var ayahNumberLocations: [AyahNumberLocation] = []
    @Published var highlights: QuranHighlights
    @Published var scrollToVerse: AyahNumber?

    @Published var scale: WordFrameScale = .zero
    @Published var imageFrame: CGRect = .zero

    var imageRenderingMode: QuranThemedImage.RenderingMode {
        reading.usesInvertedQuranImageRenderingInDarkMode ? .invertInDarkMode : .tinted
    }

    var decorations: ImageDecorations {
        // Add verse highlights
        var frameHighlights: [WordFrame: Color] = [:]
        let versesByHighlights = highlights.versesByHighlights()
        for (ayah, color) in versesByHighlights {
            for frame in imagePage?.wordFrames.wordFramesForVerse(ayah) ?? [] {
                frameHighlights[frame] = Color(color)
            }
        }

        // Add word highlights. The recited word is drawn last, so it wins the rare frame
        // where the reader has dragged the pointer onto the word being recited.
        if let word = highlights.pointedWord, let frame = imagePage?.wordFrames.wordFrameForWord(word) {
            frameHighlights[frame] = QuranHighlights.wordHighlightColor
        }
        if let word = highlights.recitedWord, let frame = imagePage?.wordFrames.wordFrameForWord(word) {
            // The recited word sits on top of its ayah's reading highlight, so it needs a
            // stronger tint than the drag pointer, which has no tint underneath it.
            frameHighlights[frame] = QuranHighlights.recitedWordHighlightColor
        }

        return ImageDecorations(
            suraHeaders: suraHeaderLocations,
            ayahNumbers: ayahNumberLocations,
            wordFrames: imagePage?.wordFrames ?? WordFrameCollection(lines: []),
            highlights: frameHighlights
        )
    }

    func loadImagePage() async {
        guard ReadingPreferences.shared.reading == reading else {
            return
        }

        do {
            let imagePage = try await imageDataService.imageForPage(page)
            try Task.checkCancellation()
            guard ReadingPreferences.shared.reading == reading else {
                return
            }
            self.imagePage = imagePage

            if reading == .hafs_1421 {
                suraHeaderLocations = try await imageDataService.suraHeaders(page)
                ayahNumberLocations = try await imageDataService.ayahNumbers(page)
            }

            scrollToVerseIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            guard ReadingPreferences.shared.reading == reading else {
                return
            }
            // TODO: should show error to the user
            crasher.recordError(error, reason: "Failed to retrieve quran image details")
        }
    }

    func wordAtGlobalPoint(_ point: CGPoint) -> Word? {
        let localPoint = CGPoint(
            x: point.x - imageFrame.minX,
            y: point.y - imageFrame.minY
        )
        return imagePage?.wordFrames.wordAtLocation(localPoint, imageScale: scale)
    }

    /// The inverse of `wordAtGlobalPoint`: where a word sits on screen.
    func globalRectForWord(_ word: Word) -> CGRect? {
        guard let frame = imagePage?.wordFrames.wordFrameForWord(word) else {
            return nil
        }
        return frame.rect
            .scaled(by: scale)
            .offsetBy(dx: imageFrame.minX, dy: imageFrame.minY)
    }

    // MARK: Private

    private let imageDataService: ImageDataService
    private let highlightsService: QuranHighlightsService
    private let reading: Reading
    private var cancellables: Set<AnyCancellable> = []

    private func scrollToVerseIfNeededSynchronously() {
        guard let ayah = highlightsService.highlights.firstScrollingVerse() else {
            return
        }
        logger.info("Quran Image: scrollToVerseIfNeeded \(ayah)")
        scrollToVerse = ayah
    }

    private func scrollToVerseIfNeeded() {
        // Execute in the next runloop to allow the highlightsService value to load.
        DispatchQueue.main.async {
            self.scrollToVerseIfNeededSynchronously()
        }
    }
}
