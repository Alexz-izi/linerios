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
                switch selectedSection {
                case .playlists:
                    ForEach(libraryStore.playlists) { playlist in
                        playlistRow(playlist)
                    }
                case .likedSongs:
                    ForEach(libraryStore.savedTracks) { track in
                        trackRow(track)
                    }
                case .offlineLyrics:
                    offlineLyricsInfoView
                }

                Color.clear.frame(height: 120)
            }
        }
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
        NavigationStack {
            VStack(spacing: 20) {
                if let url = playlist.imageURL {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(spacing: 4) {
                    Text(playlist.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text("By \(playlist.ownerName) · \(playlist.totalItems) songs")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textMuted)
                }

                HStack(spacing: 12) {
                    Button(action: {
                        playerStore.playTrack(uri: playlist.uri)
                        selectedPlaylist = nil
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.bgPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(theme.activeAccent)
                        .clipShape(Capsule())
                    }

                    Button(action: {
                        libraryStore.preWarmLyrics(for: playlist.id)
                        selectedPlaylist = nil
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Cache Lyrics")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(theme.currentPreset.glassTintColor)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { selectedPlaylist = nil }
                }
            }
        }
    }
}
