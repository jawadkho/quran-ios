//
//  QuranHighlightsService.swift
//
//
//  Created by Mohamed Afifi on 2023-12-23.
//

import Combine
import QuranAnnotations
import VLogging

public final class QuranHighlightsService {
    // MARK: Lifecycle

    public init() { }

    // MARK: Public

    @Published public var highlights = QuranHighlights() {
        didSet {
            // A heuristic, not a precise test: following a recitation rewrites the
            // recited word a few times a second and nothing else, and logging those would
            // bury every other highlight change. A write that changes the recited word
            // alongside something else, as `reset()` can, is skipped too.
            if highlights.recitedWord == oldValue.recitedWord {
                logger.info("Highlights updated")
            }
        }
    }

    public var scrolling: AnyPublisher<Void, Never> {
        $highlights
            .zip($highlights.dropFirst())
            .filter { oldValue, newValue in
                newValue.needsScrolling(comparingTo: oldValue)
            }
            .map { _ in }
            .eraseToAnyPublisher()
    }

    public func reset() {
        highlights = QuranHighlights()
    }
}
