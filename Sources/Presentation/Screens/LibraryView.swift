//
//  LibraryView.swift
//  LineriOS
//
//  Screen S6: Spotify library, saved playlists, liked tracks,
//  and background batch lyrics pre-warmer.
//

import SwiftUI

public enum LibrarySection: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
    case likedSongs = "Liked Songs"
    case recent = "Recent"
    case offlineLyrics = "Offline Lyrics"

    public var id: String { rawValue }
}

public struct LibraryView: View {
    @Bindable private var libraryStore = LibraryStore.shared
    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared

    @State private var selectedSection: LibrarySection = .playlists
    @State private var selectedPlaylist: PlaylistSummary?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveAtmosphereMeshView()

                VStack(spacing: 16) {
                    // Header (Top 59pt safe-area)
                    headerSection
                        .padding(.top, 59)

                    // Segmented Filter Bar
                    segmentedSectionBar

                    // Batch Pre-Warmer Status Banner (if active)
                    if libraryStore.isPreWarming {
                        preWarmerBanner
                    }

                    // Content Section
                    contentSection
                }
                .padding(.horizontal, 20)
            }
            .ignoresSafeArea()
            .sheet(item: $selectedPlaylist) { playlist in
                playlistDetailSheet(playlist)
            }
            .task {
                await libraryStore.loadLibrary()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Text("Your Library")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Spacer()

            Button(action: {
                Task { await libraryStore.loadLibrary() }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(theme.currentPreset.bgSecondary)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Segmented Section Bar
    private var segmentedSectionBar: some View {
        HStack(spacing: 8) {
            ForEach(LibrarySection.allCases) { section in
                Button(action: {
                    selectedSection = section
                }) {
                    Text(section.rawValue)
                        .font(.system(size: 13, weight: selectedSection == section ? .bold : .medium, design: .rounded))
                        .foregroundColor(selectedSection == section ? theme.activeAccent : theme.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedSection == section ? theme.activeAccent.opacity(0.18) : theme.currentPreset.bgSecondary
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(theme.specularRimColor.opacity(0.2), lineWidth: 0.8)
                        )
                }
            }
            Spacer()
        }
    }

    // MARK: - Pre-Warmer Banner
    private var preWarmerBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(theme.activeAccent)
                Text(libraryStore.preWarmStatusText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
            }

            ProgressView(value: libraryStore.preWarmProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: theme.activeAccent))
        }
        .padding(12)
        .background(theme.currentPreset.glassTintColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Main Content
    private var contentSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if libraryStore.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.activeAccent))
                            .scaleEffect(1.2)
                        Text("Syncing with Spotify...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    switch selectedSection {
                    case .playlists:
                        if libraryStore.playlists.isEmpty {
                            emptyLibraryCard(
                                title: "No Playlists Loaded",
                                subtitle: "Authorize Spotify Web access to view your private and followed playlists.",
                                showConnectButton: true
                            )
                            if !libraryStore.recentlyPlayed.isEmpty {
                                recentlyPlayedFallbackList
                            }
                        } else {
                            ForEach(libraryStore.playlists) { playlist in
                                playlistRow(playlist)
                            }
                        }
                    case .likedSongs:
                        if libraryStore.savedTracks.isEmpty {
                            emptyLibraryCard(
                                title: "No Liked Songs Loaded",
                                subtitle: "Connect your Spotify account to synchronize your favorite tracks.",
                                showConnectButton: true
                            )
                            if !libraryStore.recentlyPlayed.isEmpty {
                                recentlyPlayedFallbackList
                            }
                        } else {
                            ForEach(libraryStore.savedTracks) { track in
                                trackRow(track)
                            }
                        }
                    case .recent:
                        if libraryStore.recentlyPlayed.isEmpty {
                            emptyLibraryCard(
                                title: "No Recent Tracks",
                                subtitle: "Play any track on Spotify or in LineriOS to build your local listening history.",
                                showConnectButton: false
                            )
                        } else {
                            ForEach(libraryStore.recentlyPlayed) { track in
                                trackRow(track)
                            }
                        }
                    case .offlineLyrics:
                        offlineLyricsInfoView
                    }
                }

                Color.clear.frame(height: 120)
            }
        }
    }

    private var recentlyPlayedFallbackList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECENTLY PLAYED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)
                .padding(.top, 16)
                .padding(.leading, 4)

            ForEach(libraryStore.recentlyPlayed) { track in
                trackRow(track)
            }
        }
    }

    private func emptyLibraryCard(title: String, subtitle: String, showConnectButton: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 36))
                .foregroundColor(theme.activeAccent.opacity(0.8))
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                if showConnectButton {
                    Button {
                        Task {
                            try? await libraryStore.authorizeFullLibrary()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.open.fill")
                            Text("Connect Spotify Account")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(theme.activeAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task {
                        await libraryStore.loadLibrary()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.top, 16)
    }

    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        Button(action: { selectedPlaylist = playlist }) {
            HStack(spacing: 14) {
                if let url = playlist.imageURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.currentPreset.bgSecondary)
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: "music.note.list").foregroundColor(theme.activeAccent))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text("\(playlist.ownerName) · \(playlist.totalItems) tracks")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: TrackItem) -> some View {
        Button(action: {
            playerStore.playTrack(track)
        }) {
            HStack(spacing: 12) {
                if let url = track.artworkURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(track.artistName)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.textMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var offlineLyricsInfoView: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 40)
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 40))
                .foregroundColor(theme.activeAccent)
            Text("Permanent SQLite WAL Storage")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)
            Text("All fetched lyrics are preserved permanently in Documents/liner_cache.sqlite with zero network dependency.")
                .font(.system(size: 13))
                .foregroundColor(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Playlist Detail Sheet
    private func playlistDetailSheet(_ playlist: PlaylistSummary) -> some View {
        PlaylistDetailView(playlist: playlist) {
            selectedPlaylist = nil
        }
    }
}

// MARK: - Dedicated Playlist Detail View
struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    let onClose: () -> Void

    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared
    @Bindable private var libraryStore = LibraryStore.shared

    @State private var tracks: [TrackItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveAtmosphereMeshView()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Artwork & Meta Header
                        VStack(spacing: 12) {
                            if let url = playlist.imageURL {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(LinearGradient(colors: [Color.white.opacity(0.4), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                                )
                                .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
                            } else {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(theme.currentPreset.bgSecondary)
                                    .frame(width: 160, height: 160)
                                    .overlay(Image(systemName: "music.note.list").font(.system(size: 48)).foregroundColor(theme.activeAccent))
                            }

                            VStack(spacing: 4) {
                                Text(playlist.name)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(theme.textPrimary)
                                    .multilineTextAlignment(.center)
                                Text("By \(playlist.ownerName) · \(playlist.totalItems) songs")
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textMuted)
                            }

                            // Play / Cache Action Buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    if let first = tracks.first {
                                        playerStore.playTrack(first)
                                    } else {
                                        playerStore.playTrack(uri: playlist.uri)
                                    }
                                    onClose()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                        Text("Play All")
                                    }
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .background(theme.activeAccent)
                                    .clipShape(Capsule())
                                    .shadow(color: theme.activeAccent.opacity(0.35), radius: 10, x: 0, y: 5)
                                }

                                Button(action: {
                                    libraryStore.preWarmLyrics(for: playlist.id)
                                    onClose()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Cache Lyrics")
                                    }
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(theme.textPrimary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(theme.currentPreset.glassTintColor)
                                    }
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(.top, 20)

                        Divider().background(Color.white.opacity(0.12))
                            .padding(.horizontal, 20)

                        // Track List Section
                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: theme.activeAccent))
                                Text("Loading tracks...")
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textMuted)
                            }
                            .padding(.top, 30)
                        } else if tracks.isEmpty {
                            Text(errorMessage ?? "No tracks found in this playlist.")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textMuted)
                                .padding(.top, 30)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(tracks) { track in
                                    Button(action: {
                                        playerStore.playTrack(track)
                                    }) {
                                        HStack(spacing: 12) {
                                            if let url = track.artworkURL {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable().aspectRatio(contentMode: .fill)
                                                    } else {
                                                        Color.gray.opacity(0.3)
                                                    }
                                                }
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            } else {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(theme.currentPreset.bgSecondary)
                                                    .frame(width: 44, height: 44)
                                                    .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(theme.textMuted))
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    .foregroundColor(theme.textPrimary)
                                                    .lineLimit(1)
                                                Text(track.artistName)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(theme.textMuted)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Text(track.formattedDuration)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(theme.textMuted)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white.opacity(0.04))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(theme.textMuted)
                    }
                }
            }
            .task {
                do {
                    self.tracks = try await SpotifyWebAPIClient.shared.getPlaylistItems(playlistId: playlist.id)
                    self.isLoading = false
                } catch {
                    self.isLoading = false
                    self.errorMessage = "Failed to load playlist: \(error.localizedDescription)"
                }
            }
        }
    }
}
