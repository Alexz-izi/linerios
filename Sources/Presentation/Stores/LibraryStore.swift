//
//  LibraryStore.swift
//  LineriOS
//
//  MainActor observable library store managing saved tracks, playlists,
//  and background batch lyrics pre-warming (650ms fair-use rate limiting).
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
public final class LibraryStore {
    public static let shared = LibraryStore()

    public var playlists: [PlaylistSummary] = []
    public var savedTracks: [TrackItem] = []
    public var isLoading: Bool = false
    public var isPreWarming: Bool = false
    public var preWarmProgress: Double = 0.0
    public var preWarmStatusText: String = ""

    private let apiClient = SpotifyWebAPIClient.shared
    private let lyricsRepo = CompositeLyricsRepository.shared

    public init() {}

    public func loadLibrary() async {
        isLoading = true
        async let playlistsFetch = apiClient.getPlaylists(limit: 10, offset: 0)
        async let tracksFetch = apiClient.getSavedTracks(limit: 10, offset: 0)

        do {
            let (fetchedPlaylists, fetchedTracks) = try await (playlistsFetch, tracksFetch)
            self.playlists = fetchedPlaylists
            self.savedTracks = fetchedTracks
            self.isLoading = false
        } catch {
            self.isLoading = false
            RingBufferLogger.shared.log(level: .warn, category: "Library", message: "Library load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Lyrics Pre-Warmer (650ms Fair-Use Interval)

    public func preWarmLyrics(for playlistId: String) {
        guard !isPreWarming else { return }
        isPreWarming = true
        preWarmProgress = 0.0
        preWarmStatusText = "Fetching playlist tracks..."

        Task {
            do {
                let items = try await apiClient.getPlaylistItems(playlistId: playlistId, offset: 0)
                guard !items.isEmpty else {
                    isPreWarming = false
                    preWarmStatusText = "Playlist is empty."
                    return
                }

                for (idx, track) in items.enumerated() {
                    preWarmProgress = Double(idx) / Double(items.count)
                    preWarmStatusText = "Caching (\(idx + 1)/\(items.count)): \(track.title)"

                    _ = try? await lyricsRepo.getOrFetchLyrics(
                        trackURI: track.uri,
                        title: track.title,
                        artist: track.artistName,
                        album: track.albumName,
                        durationMs: track.durationMs
                    )

                    // 650ms delay between fetches to strictly adhere to LRCLIB fair-use guidelines
                    try? await Task.sleep(for: .milliseconds(650))
                }

                preWarmProgress = 1.0
                preWarmStatusText = "Completed! All lyrics cached in SQLite."
                try? await Task.sleep(for: .seconds(2))
                isPreWarming = false
            } catch {
                isPreWarming = false
                preWarmStatusText = "Pre-warming stopped: \(error.localizedDescription)"
            }
        }
    }
}
