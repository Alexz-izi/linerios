//
//  AdaptiveAtmosphereMeshView.swift
//  LineriOS
//
//  Dynamic 3x3 MeshGradient ambient atmosphere background driven by vImage LAB palette extraction.
//  Preserves >= 5.52:1 WCAG AA text contrast while animating color nodes smoothly.
//

import SwiftUI

public struct AdaptiveAtmosphereMeshView: View {
    @Bindable private var theme = ThemeManager.shared
    @State private var phase: Double = 0.0

    public init() {}

    public var body: some View {
        ZStack {
            theme.currentPreset.bgPrimary.ignoresSafeArea()

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
                        theme.meshColor0, theme.meshColor1, theme.meshColor0,
                        theme.meshColor1, theme.meshColor2.opacity(0.45), theme.meshColor1,
                        theme.meshColor0, theme.meshColor3, theme.meshColor0
                    ]
                )
                .blur(radius: 50)
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [theme.meshColor2.opacity(0.35), theme.meshColor0],
                    center: .center,
                    startRadius: 20,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
}
