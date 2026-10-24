//
//  PlayerStore.swift
//  LineriOS
//
//  MainActor observable view model orchestrating playback snapshots, interactive scrubbing,
//  and transport actions across NowPlayingView, MiniPlayer, and the 120Hz clock engine.
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
public final class PlayerStore {
    public static let shared = PlayerStore()

    public var currentSnapshot: PlaybackSnapshot?
    public var connectionState: PlaybackConnectionState = .disconnected
    public var isScrubbing: Bool = false
    public var scrubberPositionMs: Double = 0.0

    private let coordinator: PlaybackControllerProtocol

    public init(coordinator: PlaybackControllerProtocol = HybridPlaybackCoordinator.shared) {
        self.coordinator = coordinator
        bindCoordinator()
    }

    private func bindCoordinator() {
        self.connectionState = coordinator.connectionState
        self.currentSnapshot = coordinator.currentSnapshot

        coordinator.onSnapshotUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.currentSnapshot = snapshot
            if !self.isScrubbing {
                self.scrubberPositionMs = Double(snapshot.anchorPositionMs)
            }
        }
    }

    // MARK: - State Properties

    public var isPlaying: Bool {
        currentSnapshot?.isPlaying ?? false
    }

    public var trackTitle: String {
        currentSnapshot?.title ?? "Not Playing"
    }

    public var artistName: String {
        currentSnapshot?.artist ?? "Connect to Spotify"
    }

    public var albumName: String {
        currentSnapshot?.album ?? ""
    }

    public var artworkURL: URL? {
        currentSnapshot?.artworkURL
    }

    public var durationMs: Int {
        currentSnapshot?.durationMs ?? 0
    }

    public var shuffleEnabled: Bool {
        currentSnapshot?.shuffleEnabled ?? false
    }

    public var repeatMode: RepeatMode {
        currentSnapshot?.repeatMode ?? .off
    }

    public var formattedDuration: String {
        formatMs(durationMs)
    }

    public var formattedCurrentPosition: String {
        formatMs(Int(scrubberPositionMs))
    }

    public var formattedRemainingTime: String {
        let remaining = max(0, durationMs - Int(scrubberPositionMs))
        return "-\(formatMs(remaining))"
    }

    public var progressFraction: Double {
        guard durationMs > 0 else { return 0.0 }
        return min(max(scrubberPositionMs / Double(durationMs), 0.0), 1.0)
    }

    // MARK: - User Actions

    public func connect() async {
        do {
            try await coordinator.connect()
            self.connectionState = coordinator.connectionState
        } catch {
            self.connectionState = .error(error.localizedDescription)
        }
    }

    public func togglePlayPause() {
        Task {
            do {
                if isPlaying {
                    try await coordinator.pause()
                } else {
                    try await coordinator.play(uri: nil)
                }
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Toggle failed: \(error.localizedDescription)")
            }
        }
    }

    public func skipNext() {
        Task {
            do {
                try await coordinator.skipNext()
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Skip next failed: \(error.localizedDescription)")
            }
        }
    }

    public func skipPrevious() {
        Task {
            do {
                try await coordinator.skipPrevious()
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Skip previous failed: \(error.localizedDescription)")
            }
        }
    }

    public func playTrack(uri: String) {
        Task {
            do {
                try await coordinator.play(uri: uri)
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Play track failed: \(error.localizedDescription)")
            }
        }
    }

    public func beginScrubbing() {
        isScrubbing = true
    }

    public func updateScrubbing(fraction: Double) {
        let clamped = min(max(fraction, 0.0), 1.0)
        scrubberPositionMs = clamped * Double(durationMs)
    }

    public func finishScrubbing() {
        isScrubbing = false
        let targetMs = Int(scrubberPositionMs)
        Task {
            do {
                try await coordinator.seek(toPositionMs: targetMs)
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Seek failed: \(error.localizedDescription)")
            }
        }
    }

    public func toggleShuffle() {
        Task {
            do {
                try await coordinator.setShuffle(!shuffleEnabled)
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Toggle shuffle failed: \(error.localizedDescription)")
            }
        }
    }

    public func cycleRepeatMode() {
        let nextMode: RepeatMode
        switch repeatMode {
        case .off: nextMode = .context
        case .context: nextMode = .track
        case .track: nextMode = .off
        }

        Task {
            do {
                try await coordinator.setRepeatMode(nextMode)
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "PlayerStore", message: "Cycle repeat failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Utilities

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
