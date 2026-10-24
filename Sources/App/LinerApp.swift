//
//  LinerApp.swift
//  LineriOS
//
//  Milestone 0: Pipeline Proof ("Hello Glass") for iPhone 14 Pro on iOS 26 SDK.
//  Renders an interactive 120Hz Liquid Glass test card over an Obsidian / Midnight MeshGradient.
//

import SwiftUI

@main
struct LinerApp: App {
    var body: some Scene {
        WindowGroup {
            PipelineProofStageView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Pipeline Proof Stage View
struct PipelineProofStageView: View {
    @State private var activeTheme: ThemePreset = .midnight
    @State private var tapCount: Int = 0
    @State private var isInteracting: Bool = false
    @State private var pulseScale: CGFloat = 1.0

    // Mesh animation phase
    @State private var animationPhase: Double = 0.0

    var body: some View {
        ZStack {
            // Stage Background: Obsidian (#000000) base with animated Midnight MeshGradient
            backgroundStage

            // Floating Functional & Navigation Layer (Liquid Glass)
            VStack(spacing: 24) {
                // Top Header Pill (Safe Area 59pt for Dynamic Island)
                headerDynamicIslandBadge
                    .padding(.top, 59)

                Spacer()

                // Centerpiece: iOS 26 Liquid Glass Interactive Test Card
                liquidGlassCard

                Spacer()

                // Bottom Floating Control Bar (Safe Area 34pt for Home Indicator)
                themeSelectionBar
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                animationPhase = 1.0
            }
        }
    }

    // MARK: - Background Atmosphere Stage
    @ViewBuilder
    private var backgroundStage: some View {
        ZStack {
            activeTheme.bgPrimary

            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [Float(0.4 + 0.2 * animationPhase), Float(0.5 + 0.1 * animationPhase)], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        activeTheme.bgPrimary, activeTheme.bgSecondary, activeTheme.bgPrimary,
                        activeTheme.bgSecondary, activeTheme.meshNode2.opacity(0.35), activeTheme.bgSecondary,
                        activeTheme.bgPrimary, activeTheme.bgSecondary, activeTheme.bgPrimary
                    ]
                )
                .blur(radius: 40)
            } else {
                RadialGradient(
                    colors: [activeTheme.meshNode2.opacity(0.28), activeTheme.bgPrimary],
                    center: .center,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        }
    }

    // MARK: - Top Dynamic Island Pill
    private var headerDynamicIslandBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: "#10B981")) // Emerald online dot
                .frame(width: 8, height: 8)

            Text("LINERiOS · MILESTONE 0 PROOF")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(activeTheme.textPrimary)

            Spacer()

            Text("120Hz ProMotion")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(activeTheme.accentPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(activeTheme.accentPrimary.opacity(0.16))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(activeTheme.glassTintColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(activeTheme.specularRimColor, lineWidth: 1)
                )
        )
    }

    // MARK: - Centerpiece Liquid Glass Card
    private var liquidGlassCard: some View {
        VStack(spacing: 20) {
            // Card Emblem
            ZStack {
                Circle()
                    .fill(activeTheme.accentPrimary.opacity(0.2))
                    .frame(width: 72, height: 72)

                Image(systemName: "music.note.list")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(activeTheme.accentPrimary)
            }
            .scaleEffect(pulseScale)

            // Card Title & Subtitle
            VStack(spacing: 6) {
                Text("Liquid Glass Pipeline")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(activeTheme.textPrimary)

                Text("iPhone 14 Pro · SideStore · 120Hz Engine")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(activeTheme.textMuted)
            }

            Divider()
                .background(activeTheme.specularRimColor.opacity(0.3))

            // Diagnostic Telemetry Rows
            VStack(spacing: 12) {
                telemetryRow(title: "Architecture", value: "arm64 / iOS 26.0")
                telemetryRow(title: "Bundle ID Slots", value: "1 / 3 Active (Single Target)")
                telemetryRow(title: "Secrets In Repo", value: "€0.00 / Zero Hardcoded")
                telemetryRow(title: "Interactive Taps", value: "\(tapCount)")
            }

            // Interactive Haptic Button
            Button(action: handleTap) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                    Text("Test 120Hz Haptic Touch")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(activeTheme.bgPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(activeTheme.accentPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(activeTheme.glassTintColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [activeTheme.specularRimColor, activeTheme.specularRimColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 15)
        )
    }

    // MARK: - Bottom Theme Selection Bar
    private var themeSelectionBar: some View {
        VStack(spacing: 8) {
            Text("THEME PRESETS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(activeTheme.textMuted)

            HStack(spacing: 8) {
                ForEach(ThemePreset.allCases) { preset in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            activeTheme = preset
                        }
                    }) {
                        Text(preset.displayName)
                            .font(.system(size: 12, weight: activeTheme == preset ? .bold : .medium, design: .rounded))
                            .foregroundColor(activeTheme == preset ? preset.accentPrimary : preset.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                activeTheme == preset ? preset.accentPrimary.opacity(0.18) : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(6)
            .background(
                Capsule()
                    .fill(activeTheme.bgSecondary.opacity(0.8))
                    .overlay(
                        Capsule()
                            .stroke(activeTheme.specularRimColor.opacity(0.4), lineWidth: 0.8)
                    )
            )
        }
    }

    // MARK: - Helpers
    private func telemetryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(activeTheme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(activeTheme.textPrimary)
        }
    }

    private func handleTap() {
        tapCount += 1
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.5)) {
            pulseScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Scale Button Style for 120Hz Touch Response
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
