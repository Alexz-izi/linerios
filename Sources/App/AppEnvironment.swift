//
//  AppEnvironment.swift
//  LineriOS
//
//  Core Dependency Injection and Lifecycle Container for LineriOS.
//  Coordinates PlayerStore, LyricsStore, ThemeManager, LibraryStore, and SearchStore.
//

import SwiftUI
import Observation

@MainActor
@Observable
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    
    public let themeManager: ThemeManager
    public let playerStore: PlayerStore
    public let lyricsStore: LyricsStore
    public let libraryStore: LibraryStore
    public let searchStore: SearchStore
    
    public var selectedTab: TabIndex = .home
    public var isNowPlayingPresented: Bool = false
    public var isLyricsPresented: Bool = false
    
    public enum TabIndex: Int, Hashable {
        case home = 0
        case search = 1
        case library = 2
        case settings = 3
    }
    
    private init() {
        self.themeManager = ThemeManager.shared
        self.playerStore = PlayerStore.shared
        self.lyricsStore = LyricsStore.shared
        self.libraryStore = LibraryStore.shared
        self.searchStore = SearchStore.shared
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Track changes update palette extraction and fetch lyrics
        _ = withObservationTracking {
            playerStore.currentTrack
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.setupBindings()
                guard let track = self.playerStore.currentTrack else { return }
                
                // Fetch lyrics for new track
                await self.lyricsStore.loadLyrics(
                    trackId: track.id,
                    trackName: track.name,
                    artistName: track.artistName,
                    albumName: track.albumName,
                    durationMs: track.durationMs
                )
                
                // Extract palette for atmosphere mesh
                if let urlString = track.artworkUrl, let url = URL(string: urlString) {
                    await self.themeManager.extractDynamicPalette(from: url)
                }
            }
        }
    }
    
    public func handleOpenURL(_ url: URL) {
        if url.scheme == "linerios" && url.host == "auth-callback" {
            SpotifyPKCEAuthenticator.shared.handleCallbackURL(url)
        }
    }
}
