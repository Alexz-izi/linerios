//
//  SystemStatusModals.swift
//  LineriOS
//
//  Screen S12: System Status, Reconnection Alerts & Network Guardrails.
//  Non-intrusive floating glass banners for Spotify App Sleep (SPTAppRemote offline),
//  HTTP 429 Rate Limit Cooldown, and Offline Network indicators.
//

import SwiftUI

public struct SystemStatusBannerView: View {
    let isSpotifyOffline: Bool
    let rateLimitRemainingSeconds: Int?
    let isNetworkOffline: Bool
    let onWakeSpotify: () -> Void
    
    public init(
        isSpotifyOffline: Bool,
        rateLimitRemainingSeconds: Int?,
        isNetworkOffline: Bool,
        onWakeSpotify: @escaping () -> Void
    ) {
        self.isSpotifyOffline = isSpotifyOffline
        self.rateLimitRemainingSeconds = rateLimitRemainingSeconds
        self.isNetworkOffline = isNetworkOffline
        self.onWakeSpotify = onWakeSpotify
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            if let seconds = rateLimitRemainingSeconds, seconds > 0 {
                rateLimitBanner(seconds: seconds)
            }
            
            if isNetworkOffline {
                networkOfflineBanner
            }
            
            if isSpotifyOffline {
                spotifySleepBanner
            }
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSpotifyOffline)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rateLimitRemainingSeconds)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isNetworkOffline)
    }
    
    // MARK: - Banner Variants
    
    private func rateLimitBanner(seconds: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Spotify API Cooldown Active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Pausing requests for \(seconds)s to prevent rate limiting.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    private var networkOfflineBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.red)
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline Mode Active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Serving synced lyrics and palettes from local SQLite cache.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    private var spotifySleepBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.cyan)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Spotify Local IPC Disconnected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Tap Wake to reconnect local audio session.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            
            Button {
                onWakeSpotify()
            } label: {
                Text("Wake")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.cyan)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
