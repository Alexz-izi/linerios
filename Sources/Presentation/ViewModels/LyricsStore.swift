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

    // MARK: - Active Line & Syllable Resolution

    private func resolveActiveLine(for timeMs: Int) {
        guard let lines = lyrics?.lines, !lines.isEmpty else {
            activeLineIndex = nil
            return
        }

        // Fast binary search to find active line
        var low = 0
        var high = lines.count - 1
        var candidateIndex: Int?

        while low <= high {
            let mid = (low + high) / 2
            let line = lines[mid]

            if timeMs >= line.startTimeMs && timeMs < line.endTimeMs {
                candidateIndex = mid
                break
            } else if timeMs < line.startTimeMs {
                high = mid - 1
            } else {
                candidateIndex = mid // Best preceding line
                low = mid + 1
            }
        }

        if self.activeLineIndex != candidateIndex {
            self.activeLineIndex = candidateIndex
        }
    }

    // MARK: - Visual Helpers

    public func blurForLine(index: Int) -> Double {
        guard let active = activeLineIndex else { return 0.0 }
        let distance = abs(index - active)
        if distance == 0 { return 0.0 }
        return min(Double(distance) * 1.5, 4.0)
    }

    public func opacityForLine(index: Int) -> Double {
        guard let active = activeLineIndex else { return 0.7 }
        let distance = abs(index - active)
        if distance == 0 { return 1.0 }
        if distance == 1 { return 0.45 }
        return 0.25
    }

    public func progressForWord(_ token: LyricWordToken) -> Double {
        return token.progress(at: currentPlaybackTimeMs)
    }

    // MARK: - User Offset Stepper (±100ms)

    public func adjustOffset(by deltaMs: Int) {
        userOffsetMs += deltaMs
        clock.setUserOffset(ms: userOffsetMs)

        if let uri = activeTrackURI {
            Task {
                try? await repository.updateUserOffset(trackURI: uri, offsetMs: userOffsetMs)
            }
        }
    }

    public func resetOffset() {
        adjustOffset(by: -userOffsetMs)
    }
}
