//
//  NowPlayingView.swift
//  LineriOS
//
//  Screen S7: Flagship full-screen player combining adaptive atmosphere mesh,
//  120Hz interactive scrubbing, Liquid Glass transport controls, and lyrics transition.
//

import SwiftUI

public struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared
    @State private var showLyricsView: Bool = false
    @State private var isLiked: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            // Adaptive Atmosphere Background
            AdaptiveAtmosphereMeshView()

            VStack(spacing: 28) {
                // Top Dismiss Bar & Device Badge
                topBarSection
                    .padding(.top, 59) // Dynamic Island 59pt safe-area inset

                Spacer()

                // Large Hero Artwork Tile (300x300pt)
                heroArtworkTile

                Spacer()

                // Track Metadata & Like Heart
                metadataRow

                // 120Hz Interactive Scrubber
                scrubberSection

                // Liquid Glass Transport Controls
                transportControlsBar

                // Bottom Lyrics & Extra Controls
                bottomUtilityBar
                    .padding(.bottom, 34) // Home indicator 34pt safe-area inset
            }
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showLyricsView) {
            LyricsView()
        }
        .onChange(of: playerStore.artworkURL) { _, newURL in
            theme.updateArtwork(url: newURL)
        }
    }

    // MARK: - Top Bar
    private var topBarSection: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.textMuted)
            }

            Spacer()

            // Active Connect Device Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#10B981"))
                    .frame(width: 6, height: 6)
                Text(playerStore.currentSnapshot?.activeDeviceName ?? "iPhone 14 Pro")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.currentPreset.bgSecondary.opacity(0.8))
            .clipShape(Capsule())

            Spacer()

            // More Options
            Button(action: {}) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(theme.textMuted)
            }
        }
    }

    // MARK: - Hero Artwork (300x300pt)
    private var heroArtworkTile: some View {
        ZStack {
            if let url = playerStore.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        artworkPlaceholder
                    }
                }
            } else {
                artworkPlaceholder
            }
        }
        .frame(width: 300, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [theme.specularRimColor, theme.specularRimColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 35, x: 0, y: 20)
    }

    private var artworkPlaceholder: some View {
        ZStack {
            theme.currentPreset.bgSecondary
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(theme.activeAccent.opacity(0.6))
        }
    }

    // MARK: - Metadata Row
    private var metadataRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playerStore.trackTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Text(playerStore.artistName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            // Like Heart Button
            Button(action: {
                isLiked.toggle()
                if let uri = playerStore.currentSnapshot?.trackURI {
                    Task {
                        if isLiked {
                            try? await SpotifyWebAPIClient.shared.saveTrackToLibrary(trackURI: uri)
                        } else {
                            try? await SpotifyWebAPIClient.shared.removeTrackFromLibrary(trackURI: uri)
                        }
                    }
                }
            }) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundColor(isLiked ? Color(hex: "#F43F5E") : theme.textMuted)
            }
        }
    }

    // MARK: - Scrubber Section
    private var scrubberSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(theme.currentPreset.bgSecondary.opacity(0.8))
                        .frame(height: 6)

                    // Progress Fill
                    Capsule()
                        .fill(theme.activeAccent)
                        .frame(width: geo.size.width * playerStore.progressFraction, height: 6)

                    // Scrubber Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .offset(x: max(0, min(geo.size.width * playerStore.progressFraction - 7, geo.size.width - 14)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            playerStore.beginScrubbing()
                            let fraction = value.location.x / geo.size.width
                            playerStore.updateScrubbing(fraction: fraction)
                        }
                        .onEnded { _ in
                            playerStore.finishScrubbing()
                        }
                )
            }
            .frame(height: 14)

            // Time Labels
            HStack {
                Text(playerStore.formattedCurrentPosition)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textMuted)

                Spacer()

                Text(playerStore.formattedRemainingTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textMuted)
            }
        }
    }

    // MARK: - Transport Controls Bar
    private var transportControlsBar: some View {
        HStack(spacing: 24) {
            // Shuffle
            Button(action: { playerStore.toggleShuffle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(playerStore.shuffleEnabled ? theme.activeAccent : theme.textMuted)
            }

            Spacer()

            // Previous
            Button(action: { playerStore.skipPrevious() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(theme.textPrimary)
            }

            // Play / Pause Circle
            Button(action: { playerStore.togglePlayPause() }) {
                Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(theme.currentPreset.bgPrimary)
                    .frame(width: 68, height: 68)
                    .background(theme.activeAccent)
                    .clipShape(Circle())
                    .shadow(color: theme.activeAccent.opacity(0.4), radius: 20, x: 0, y: 10)
            }

            // Next
            Button(action: { playerStore.skipNext() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()

            // Repeat Mode
            Button(action: { playerStore.cycleRepeatMode() }) {
                Image(systemName: repeatIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(playerStore.repeatMode != .off ? theme.activeAccent : theme.textMuted)
            }
        }
        .padding(.horizontal, 8)
    }

    private var repeatIconName: String {
        switch playerStore.repeatMode {
        case .off: return "repeat"
        case .context: return "repeat"
        case .track: return "repeat.1"
        }
    }

    // MARK: - Bottom Utility Bar
    private var bottomUtilityBar: some View {
        HStack(spacing: 32) {
            Button(action: {
                showLyricsView = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 16))
                    Text("Lyrics")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.currentPreset.glassTintColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 18))
                    .foregroundColor(theme.textMuted)
            }
        }
    }
}
