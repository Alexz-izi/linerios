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
    
    public var selectedTab: Int = 0
    public var isNowPlayingPresented: Bool = false
    public var isLyricsPresented: Bool = false
    
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
            playerStore.currentSnapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.setupBindings()
                guard let snapshot = self.playerStore.currentSnapshot else { return }
                
                // Fetch lyrics for new track
                self.lyricsStore.loadLyrics(for: snapshot)
                
                // Extract palette for atmosphere mesh
                if let url = snapshot.artworkURL {
                    self.themeManager.updateArtwork(url: url)
                }
            }
        }
    }
    
    public func handleOpenURL(_ url: URL) {
        if url.scheme == "linerios" && url.host == "auth-callback" {
            let handledByRemote = SpotifyAppRemoteAdapter.shared.handleAuthCallback(url)
            if !handledByRemote {
                SpotifyPKCEAuthenticator.shared.handleCallbackURL(url)
            }
        }
    }
}
