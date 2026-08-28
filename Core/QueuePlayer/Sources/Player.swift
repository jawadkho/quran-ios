//
//  Player.swift
//  QueuePlayer
//
//  Created by Afifi, Mohamed on 5/4/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AVFoundation

@MainActor
final class Player {
    // MARK: Lifecycle

    deinit {
        rateObservation?.invalidate()
        if let timeObservation {
            player.removeTimeObserver(timeObservation)
        }
    }

    init(url: URL) {
        asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false

        rateObservation = player.observe(\AVPlayer.rate, options: [.new]) { [weak self] _, change in
            if let rate = change.newValue {
                guard let self else { return }
                Task {
                    await self.onRateChanged?(rate)
                }
            }
        }
    }

    // MARK: Internal

    var onRateChanged: (@Sendable @MainActor (Float) -> Void)?

    /// Fires while playing, on the media clock, at `timeObservationInterval`. Setting it
    /// installs the observation; clearing it removes it, so nothing is observed by default.
    var onTimeChanged: (@Sendable @MainActor (TimeInterval) -> Void)? {
        didSet { updateTimeObservation() }
    }

    let playerItem: AVPlayerItem

    var currentTime: TimeInterval {
        player.currentTime().seconds
    }

    var duration: TimeInterval {
        asset.duration.seconds
    }

    // MARK: Internal helpers (read-only)

    var isPlaying: Bool {
        player.rate != 0
    }

    func play(rate: Float) {
        player.playImmediately(atRate: rate)
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.pause()
    }

    func setRate(_ rate: Float) {
        player.rate = rate
    }

    func seek(to timeInSeconds: TimeInterval, rate: Float) {
        pause()
        player.seek(to: timeInSeconds)
        play(rate: rate)
    }

    // MARK: Private

    /// Roughly a third of the shortest recited word, so a highlight lands within a frame
    /// or two of the voice without observing more often than anything can be drawn.
    private static let timeObservationInterval = CMTime(value: 50, timescale: 1000)

    private let asset: AVURLAsset
    private let player: AVPlayer
    private var timeObservation: Any?

    private var rateObservation: NSKeyValueObservation? {
        didSet { oldValue?.invalidate() }
    }
}

private extension Player {
    func updateTimeObservation() {
        if let timeObservation {
            player.removeTimeObserver(timeObservation)
            self.timeObservation = nil
        }
        guard let onTimeChanged else {
            return
        }
        timeObservation = player.addPeriodicTimeObserver(
            forInterval: Self.timeObservationInterval,
            queue: .main
        ) { time in
            // Safe because the observer is queued on .main, and cheaper than the hop the
            // rate observation above makes. Revisit both together if that queue changes.
            MainActor.assumeIsolated {
                onTimeChanged(time.seconds)
            }
        }
    }
}

private extension AVPlayer {
    func seek(to timeInSeconds: TimeInterval) {
        let time = CMTime(seconds: timeInSeconds, preferredTimescale: 1000)
        seek(to: time)
    }
}
