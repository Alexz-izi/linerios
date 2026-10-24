//
//  LyricsStore.swift
//  LineriOS
//
//  MainActor observable view model driving the 120Hz synchronized lyrics view.
//  Coordinates with ClockInterpolator for sub-frame syllable fills and auto-scrolling targets.
//

import Foundation
import SwiftUI
import Observation
import QuartzCore

@MainActor
@Observable
public final class LyricsStore {
    public static let shared = LyricsStore()

    public var lyrics: LyricsPayload?
    public var activeLineIndex: Int?
    public var currentPlaybackTimeMs: Int = 0
    public var userOffsetMs: Int = 0
    public var isLoading: Bool = false

    private let repository: CompositeLyricsRepository
    private let clock: ClockInterpolator

    private var activeTrackURI: String?

    public init(
        repository: CompositeLyricsRepository = CompositeLyricsRepository.shared,
        clock: ClockInterpolator = ClockInterpolator.shared
    ) {
        self.repository = repository
        self.clock = clock
        bindClock()
    }

    private func bindClock() {
        clock.onTick = { [weak self] timeMs in
            guard let self = self else { return }
            self.currentPlaybackTimeMs = timeMs
            self.resolveActiveLine(for: timeMs)
        }
    }

    // MARK: - Lyrics Fetching

    public func loadLyrics(for snapshot: PlaybackSnapshot) {
        guard snapshot.trackURI != activeTrackURI else { return }
        self.activeTrackURI = snapshot.trackURI
        self.isLoading = true
        self.lyrics = nil
        self.activeLineIndex = nil

        Task {
            do {
                let payload = try await repository.getOrFetchLyrics(
                    trackURI: snapshot.trackURI,
                    title: snapshot.title,
                    artist: snapshot.artist,
                    album: snapshot.album,
                    durationMs: snapshot.durationMs
                )
                self.lyrics = payload
                self.userOffsetMs = payload?.userOffsetMs ?? 0
                self.clock.setUserOffset(ms: self.userOffsetMs)
                self.isLoading = false
                self.resolveActiveLine(for: self.currentPlaybackTimeMs)
            } catch {
                self.isLoading = false
                RingBufferLogger.shared.log(level: .warn, category: "LyricsStore", message: "Failed to load lyrics: \(error.localizedDescription)")
            }
        }
    }

    public func loadLyrics(trackId: String, trackName: String, artistName: String, albumName: String, durationMs: Int) async {
        let snapshot = PlaybackSnapshot(
            trackURI: trackId,
            title: trackName,
            artist: artistName,
            album: albumName,
            artworkURL: nil,
            durationMs: durationMs,
            anchorPositionMs: 0,
            anchorMonotonicTime: CACurrentMediaTime(),
            isPlaying: true,
            shuffleEnabled: false,
            repeatMode: .off,
            activeDeviceName: "iPhone 14 Pro"
        )
        loadLyrics(for: snapshot)
    }

    public func clearLocalCache() async {
        await SQLiteCacheActor.shared.clearLyrics()
        self.lyrics = nil
        self.activeLineIndex = nil
        self.activeTrackURI = nil
    }

    // MARK: - Manual Offset Timing Adjustment

    public func adjustOffset(deltaMs: Int) {
        self.userOffsetMs += deltaMs
        self.clock.setUserOffset(ms: userOffsetMs)

        if let uri = activeTrackURI {
            Task {
                await SQLiteCacheActor.shared.updateUserOffset(trackURI: uri, offsetMs: userOffsetMs)
            }
        }
    }

    public func adjustOffset(by deltaMs: Int) {
        adjustOffset(deltaMs: deltaMs)
    }

    public func resetOffset() {
        self.userOffsetMs = 0
        self.clock.setUserOffset(ms: 0)

        if let uri = activeTrackURI {
            Task {
                await SQLiteCacheActor.shared.updateUserOffset(trackURI: uri, offsetMs: 0)
            }
        }
    }

    // MARK: - Real-Time Resolution (120Hz)

    private func resolveActiveLine(for timeMs: Int) {
        guard let lines = lyrics?.lines, !lines.isEmpty else {
            activeLineIndex = nil
            return
        }

        // Binary search for active line interval: startTimeMs <= timeMs < next.startTimeMs
        var low = 0
        var high = lines.count - 1
        var foundIndex: Int?

        while low <= high {
            let mid = (low + high) / 2
            let line = lines[mid]

            if line.startTimeMs <= timeMs {
                if mid == lines.count - 1 || lines[mid + 1].startTimeMs > timeMs {
                    foundIndex = mid
                    break
                }
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        self.activeLineIndex = foundIndex
    }

    // MARK: - Syllable-Level Karaoke Calculation

    public func syllableProgress(for word: LyricWordToken) -> Double {
        word.progress(at: currentPlaybackTimeMs)
    }

    public func progressForWord(_ word: LyricWordToken) -> Double {
        syllableProgress(for: word)
    }

    public func isWordActive(_ word: LyricWordToken) -> Bool {
        currentPlaybackTimeMs >= word.startTimeMs && currentPlaybackTimeMs < word.endTimeMs
    }

    public func blurForLine(index: Int) -> CGFloat {
        guard let active = activeLineIndex else { return 0.0 }
        let distance = abs(active - index)
        switch distance {
        case 0: return 0.0
        case 1: return 1.5
        case 2: return 3.5
        default: return 6.0
        }
    }

    public func opacityForLine(index: Int) -> Double {
        guard let active = activeLineIndex else { return 0.5 }
        let distance = abs(active - index)
        switch distance {
        case 0: return 1.0
        case 1: return 0.65
        case 2: return 0.35
        default: return 0.15
        }
    }
}
