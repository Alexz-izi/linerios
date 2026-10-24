//
//  HomeView.swift
//  LineriOS
//
//  Screen S3: Fast-launch music hub showing active device, Jump Back In grid,
//  recently played horizontal carousel, and quick saved tracks.
//

import SwiftUI

public struct HomeView: View {
    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared
    @Bindable private var libraryStore = LibraryStore.shared

    @State private var recentTracks: [TrackItem] = []
    @State private var showSettings: Bool = false
    @State private var showFullPlayer: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveAtmosphereMeshView()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        // Top Greeting & Device Pill
                        topBarHeader
                            .padding(.top, 59) // Dynamic Island inset

                        // Section 1: Jump Back In Grid
                        jumpBackInSection

                        // Section 2: Recently Played Carousel
                        recentlyPlayedSection

                        // Section 3: Quick Saved Tracks
                        quickSavedSection

                        // Bottom Spacer for MiniPlayer
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 20)
                }
                .refreshable {
                    await loadHomeData()
                }

                // Docked Mini-Player (S8)
                VStack {
                    Spacer()
                    LiquidGlassMiniPlayer {
                        showFullPlayer = true
                    }
                    .padding(.bottom, 12)
                }
            }
            .ignoresSafeArea()
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                NowPlayingView()
            }
            .task {
                await loadHomeData()
            }
        }
    }

    // MARK: - Top Header
    private var topBarHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textMuted)

                Text("Good Music")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()

            // Active Device Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 6, height: 6)
                Text(playerStore.currentSnapshot?.activeDeviceName ?? "iPhone 14 Pro")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.currentPreset.glassTintColor)
            .clipShape(Capsule())

            // Settings Button
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(theme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(theme.currentPreset.bgSecondary)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Section 1: Jump Back In (2-column compact grid)
    private var jumpBackInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JUMP BACK IN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(recentTracks.prefix(6)) { track in
                    Button(action: {
                        playerStore.playTrack(uri: track.uri)
                    }) {
                        HStack(spacing: 10) {
                            if let url = track.artworkURL {
                                AsyncImage(url: url) { phase in
                                    if let img = phase.image {
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Color.gray.opacity(0.3)
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Text(track.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .background(theme.currentPreset.glassTintColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.specularRimColor.opacity(0.2), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Section 2: Recently Played Carousel
    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENTLY PLAYED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(recentTracks) { track in
                        Button(action: {
                            playerStore.playTrack(uri: track.uri)
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let url = track.artworkURL {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Color.gray.opacity(0.3)
                                        }
                                    }
                                    .frame(width: 140, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
                                    )
                                }

                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(theme.textPrimary)
                                    .lineLimit(1)

                                Text(track.artistName)
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.textMuted)
                                    .lineLimit(1)
                            }
                            .frame(width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Section 3: Quick Saved Tracks
    private var quickSavedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIKED SONGS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)

            LazyVStack(spacing: 8) {
                ForEach(libraryStore.savedTracks.prefix(8)) { track in
                    Button(action: {
                        playerStore.playTrack(uri: track.uri)
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
            }
        }
    }

    // MARK: - Data Loading
    private func loadHomeData() async {
        await libraryStore.loadLibrary()
        if recentTracks.isEmpty {
            self.recentTracks = libraryStore.savedTracks
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        case 17..<22: return "GOOD EVENING"
        default: return "AFTERHOURS"
        }
    }
}
