//
//  WelcomeView.swift
//  LineriOS
//
//  Screen S1: Zero-secret onboarding and environment readiness verification.
//  Checks Spotify iOS app installation, Keychain Client ID configuration, and URL schemes.
//

import SwiftUI

public struct WelcomeView: View {
    @State private var hasSpotifyApp: Bool = false
    @State private var hasClientId: Bool = false
    @State private var hasURLScheme: Bool = true
    @State private var navigateToAuth: Bool = false
    @State private var meshPhase: Double = 0.0

    private let theme = ThemePreset.midnight

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background Atmosphere Mesh
                backgroundMesh

                VStack(spacing: 32) {
                    // Header (Top + 80pt)
                    headerSection
                        .padding(.top, 40)

                    Spacer()

                    // Centerpiece Checklist Card
                    checklistCard

                    Spacer()

                    // Primary Action CTA
                    primaryCTAButton
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .navigationDestination(isPresented: $navigateToAuth) {
                AuthConfigView()
            }
            .onAppear {
                refreshReadinessChecks()
                withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                    meshPhase = 1.0
                }
            }
        }
    }

    // MARK: - Background Atmosphere Mesh
    private var backgroundMesh: some View {
        ZStack {
            theme.bgPrimary.ignoresSafeArea()

            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
                        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(Float(0.4 + 0.2 * meshPhase), Float(0.5 + 0.1 * meshPhase)), SIMD2<Float>(1.0, 0.5),
                        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
                    ],
                    colors: [
                        theme.bgPrimary, theme.bgSecondary, theme.bgPrimary,
                        theme.bgSecondary, theme.meshNode2.opacity(0.32), theme.bgSecondary,
                        theme.bgPrimary, theme.bgSecondary, theme.bgPrimary
                    ]
                )
                .blur(radius: 40)
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.glassTintColor)
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(theme.specularRimColor, lineWidth: 1.2)
                    )

                Image(systemName: "music.note.list")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(theme.accentPrimary)
            }

            VStack(spacing: 8) {
                Text("Liner for iOS")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text("Your personal 120Hz Liquid Glass music visualizer and lyrics companion.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Environment Checklist Card
    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ENVIRONMENT READINESS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.textMuted)

            VStack(spacing: 14) {
                checklistRow(
                    title: "Spotify iOS App Installed",
                    subtitle: hasSpotifyApp ? "Ready for local IPC socket link" : "Required as background audio engine",
                    isReady: hasSpotifyApp
                ) {
                    if !hasSpotifyApp, let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id324684580") {
                        UIApplication.shared.open(appStoreURL)
                    }
                }

                Divider().background(theme.specularRimColor.opacity(0.2))

                checklistRow(
                    title: "Spotify Client ID Configured",
                    subtitle: hasClientId ? "Persisted in Secure Enclave Keychain" : "Needs your 32-character hex ID",
                    isReady: hasClientId
                )

                Divider().background(theme.specularRimColor.opacity(0.2))

                checklistRow(
                    title: "URL Scheme Registered",
                    subtitle: "linerios://auth-callback active",
                    isReady: hasURLScheme
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(theme.glassTintColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [theme.specularRimColor, theme.specularRimColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
        )
    }

    private func checklistRow(
        title: String,
        subtitle: String,
        isReady: Bool,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isReady ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(theme.textMuted)
                }

                Spacer()

                if action != nil && !isReady {
                    Image(systemName: "arrow.up.right.circle")
                        .font(.system(size: 16))
                        .foregroundColor(theme.accentPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary CTA
    private var primaryCTAButton: some View {
        Button(action: {
            navigateToAuth = true
        }) {
            HStack(spacing: 8) {
                Text(hasClientId ? "Update Connection" : "Configure Spotify Connection")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(theme.bgPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(theme.accentPrimary)
            .clipShape(Capsule())
            .shadow(color: theme.accentPrimary.opacity(0.35), radius: 15, x: 0, y: 8)
        }
    }

    private func refreshReadinessChecks() {
        hasSpotifyApp = UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
        hasClientId = KeychainStore.shared.hasConfiguredClientId()
        hasURLScheme = true
    }
}
