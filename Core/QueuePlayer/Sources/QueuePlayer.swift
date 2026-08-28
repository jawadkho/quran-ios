//
//  QueuePlayer.swift
//  QueuePlayer
//
//  Created by Afifi, Mohamed on 4/23/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AVFoundation

public struct QueuePlayerActions: Sendable {
    // MARK: Lifecycle

    public init(
        playbackEnded: @Sendable @MainActor @escaping () -> Void,
        playbackRateChanged: @Sendable @MainActor @escaping (Float) -> Void,
        audioFrameChanged: @Sendable @MainActor @escaping (Int, Int, AVPlayerItem) -> Void,
        playbackTimeChanged: @Sendable @MainActor @escaping (TimeInterval) -> Void
    ) {
        self.playbackEnded = playbackEnded
        self.playbackRateChanged = playbackRateChanged
        self.audioFrameChanged = audioFrameChanged
        self.playbackTimeChanged = playbackTimeChanged
    }

    // MARK: Internal

    let playbackEnded: @Sendable @MainActor () -> Void
    let playbackRateChanged: @Sendable @MainActor (Float) -> Void
    let audioFrameChanged: @Sendable @MainActor (Int, Int, AVPlayerItem) -> Void

    /// Position within the file being played, on the media clock, while playing.
    let playbackTimeChanged: @Sendable @MainActor (TimeInterval) -> Void
}

@MainActor
public class QueuePlayer {
    // MARK: Lifecycle

    public init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
    }

    // MARK: Open

    open func play(request: AudioRequest, rate: Float) {
        player = AudioPlayer(request: request, rate: rate)
        player?.observesPlaybackTime = observesPlaybackTime
        player?.actions = newPlayerActions()
        player?.startPlaying()
    }

    // MARK: Public

    public var actions: QueuePlayerActions?

    /// Whether to report the playhead through `QueuePlayerActions.playbackTimeChanged`.
    public var observesPlaybackTime = false {
        didSet {
            guard observesPlaybackTime != oldValue else {
                return
            }
            player?.observesPlaybackTime = observesPlaybackTime
        }
    }

    public func pause() {
        player?.pause()
    }

    public func setRate(_ rate: Float) {
        player?.setRate(rate)
    }

    public func resume() {
        player?.resume()
    }

    public func stop() {
        player?.stop()
    }

    public func stepForward() {
        player?.stepForward()
    }

    public func stepBackward() {
        player?.stepBackgward()
    }

    // MARK: Private

    private var player: AudioPlayer? {
        didSet {
            oldValue?.actions = nil
        }
    }

    private func playbackEnded() {
        player = nil
        actions?.playbackEnded()
    }

    private func newPlayerActions() -> QueuePlayerActions {
        QueuePlayerActions(
            playbackEnded: { [weak self] in
                self?.playbackEnded()
            },
            playbackRateChanged: { [weak self] in
                self?.actions?.playbackRateChanged($0)
            },
            audioFrameChanged: { [weak self] in
                self?.actions?.audioFrameChanged($0, $1, $2)
            },
            playbackTimeChanged: { [weak self] in
                self?.actions?.playbackTimeChanged($0)
            }
        )
    }
}
