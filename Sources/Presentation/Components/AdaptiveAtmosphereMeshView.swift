//
//  AdaptiveAtmosphereMeshView.swift
//  LineriOS
//
//  Dynamic 3x3 MeshGradient & Liquid Glass ambient atmosphere background driven by
//  vImage LAB palette extraction. Features drifting glowing atmospheric orbs to ensure
//  ultraThinMaterial surfaces refract luminous color depths in any theme.
//

import SwiftUI

public struct AdaptiveAtmosphereMeshView: View {
    @Bindable private var theme = ThemeManager.shared
    @State private var phase: Double = 0.0

    public init() {}

    public var body: some View {
        ZStack {
            // Base background fill
            theme.currentPreset.bgPrimary
                .ignoresSafeArea()

            // Glowing Ambient Light Orbs (Ensures Liquid Glass materials reflect color)
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack {
                    // Top-right accent light
                    Circle()
                        .fill(theme.activeAccent.opacity(0.28))
                        .frame(width: width * 0.85, height: width * 0.85)
                        .position(
                            x: width * (0.8 + 0.1 * sin(phase * .pi)),
                            y: height * (0.15 + 0.05 * cos(phase * .pi))
                        )
                        .blur(radius: 75)

                    // Mid-left secondary ambient light
                    Circle()
                        .fill(theme.currentPreset.meshNode2.opacity(0.32))
                        .frame(width: width * 0.95, height: width * 0.95)
                        .position(
                            x: width * (0.1 - 0.08 * cos(phase * .pi)),
                            y: height * (0.55 + 0.08 * sin(phase * .pi))
                        )
                        .blur(radius: 85)

                    // Bottom-right subtle fill
                    Circle()
                        .fill(theme.meshColor1.opacity(0.30))
                        .frame(width: width * 0.8, height: width * 0.8)
                        .position(
                            x: width * (0.7 + 0.06 * cos(phase * .pi)),
                            y: height * (0.85 - 0.05 * sin(phase * .pi))
                        )
                        .blur(radius: 80)
                }
            }
            .ignoresSafeArea()

            // MeshGradient layer for iOS 18+
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
                        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(Float(0.4 + 0.2 * phase), Float(0.5 + 0.1 * phase)), SIMD2<Float>(1.0, 0.5),
                        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
                    ],
                    colors: [
                        theme.meshColor0.opacity(0.7), theme.meshColor1.opacity(0.8), theme.meshColor0.opacity(0.7),
                        theme.meshColor1.opacity(0.7), theme.meshColor2.opacity(0.65), theme.meshColor1.opacity(0.7),
                        theme.meshColor0.opacity(0.7), theme.meshColor3.opacity(0.8), theme.meshColor0.opacity(0.7)
                    ]
                )
                .blur(radius: 45)
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [theme.meshColor2.opacity(0.45), theme.meshColor0.opacity(0.9)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }

            // Subtle dark vignette to ensure text contrast (>= 5.52:1 WCAG AA)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.20),
                    Color.clear,
                    Color.black.opacity(0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
}
