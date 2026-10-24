//
//  LibraryStore.swift
//  LineriOS
//
//  MainActor observable library store managing saved tracks, playlists,
//  recently played tracks, and background batch lyrics pre-warming.
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
    public var recentlyPlayed: [TrackItem] = []
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var isPreWarming: Bool = false
    public var preWarmProgress: Double = 0.0
    public var preWarmStatusText: String = ""

    private let apiClient = SpotifyWebAPIClient.shared
    private let lyricsRepo = CompositeLyricsRepository.shared
    private let recentTracksKey = "liner_recently_played_tracks"

    public init() {
        loadRecentlyPlayedFromCache()
    }

    public func loadLibrary() async {
        isLoading = true
        errorMessage = nil

        // 1. Fetch playlists independently
        do {
            let fetchedPlaylists = try await apiClient.getPlaylists(limit: 50, offset: 0)
            self.playlists = fetchedPlaylists
        } catch {
            RingBufferLogger.shared.log(level: .warn, category: "Library", message: "Playlists fetch: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }

        // 2. Fetch saved tracks independently
        do {
            let fetchedTracks = try await apiClient.getSavedTracks(limit: 50, offset: 0)
            self.savedTracks = fetchedTracks
        } catch {
            RingBufferLogger.shared.log(level: .warn, category: "Library", message: "Saved tracks fetch: \(error.localizedDescription)")
            if self.errorMessage == nil {
                self.errorMessage = error.localizedDescription
            }
        }

        self.isLoading = false
    }

    public func authorizeFullLibrary() async throws {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await SpotifyPKCEAuthenticator.shared.authorize()
            await loadLibrary()
        } catch {
            self.isLoading = false
            self.errorMessage = "Authorization failed: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Recently Played Tracking & Persistence

    public func recordRecentlyPlayed(_ track: TrackItem) {
        guard !track.uri.isEmpty else { return }
        if let idx = recentlyPlayed.firstIndex(where: { $0.uri == track.uri }) {
            recentlyPlayed.remove(at: idx)
        }
        recentlyPlayed.insert(track, at: 0)
        if recentlyPlayed.count > 30 {
            recentlyPlayed.removeLast()
        }
        saveRecentlyPlayedToCache()
    }

    private func saveRecentlyPlayedToCache() {
        if let data = try? JSONEncoder().encode(recentlyPlayed) {
            UserDefaults.standard.set(data, forKey: recentTracksKey)
        }
    }

    private func loadRecentlyPlayedFromCache() {
        if let data = UserDefaults.standard.data(forKey: recentTracksKey),
           let cached = try? JSONDecoder().decode([TrackItem].self, from: data) {
            self.recentlyPlayed = cached
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
