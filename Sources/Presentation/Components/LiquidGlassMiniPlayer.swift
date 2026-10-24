//
//  LiquidGlassMiniPlayer.swift
//  LineriOS
//
//  Screen S8: Persistent floating Liquid Glass mini-player capsule hovering above
//  the 34pt bottom home indicator. Expands smoothly into NowPlayingView (S7).
//

import SwiftUI

public struct LiquidGlassMiniPlayer: View {
    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared

    public let onTap: () -> Void

    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Album Artwork with Specular Border
                artworkThumbnail

                // Track Meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerStore.trackTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    Text(playerStore.artistName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(theme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                // Play / Pause Glass Button
                Button(action: {
                    playerStore.togglePlayPause()
                }) {
                    Image(systemName: playerStore.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(theme.activeAccent.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Skip Next Button
                Button(action: {
                    playerStore.skipNext()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.textMuted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.currentPreset.glassTintColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [theme.specularRimColor, theme.specularRimColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var artworkThumbnail: some View {
        Group {
            if let url = playerStore.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholderTile
                    }
                }
            } else {
                placeholderTile
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.specularRimColor.opacity(0.3), lineWidth: 0.8)
        )
    }

    private var placeholderTile: some View {
        ZStack {
            theme.currentPreset.bgSecondary
            Image(systemName: "music.note")
                .foregroundColor(theme.activeAccent)
        }
    }
}
