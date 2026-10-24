//
//  LinerApp.swift
//  LineriOS
//
//  Production Application Entry Point & Root Shell for iPhone 14 Pro (iOS 26 SDK).
//  Coordinates Hardware Keychain Authentication, 120Hz ProMotion Engine,
//  Liquid Glass Stage, and Deep Link URL Routing.
//

import SwiftUI

@main
struct LinerApp: App {
    @State private var environment = AppEnvironment.shared
    
    var body: some Scene {
        WindowGroup {
            RootLifecycleStageView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    environment.handleOpenURL(url)
                }
        }
    }
}

// MARK: - Root Lifecycle Stage View

struct RootLifecycleStageView: View {
    @Bindable private var env = AppEnvironment.shared
    @Bindable private var playerStore = PlayerStore.shared
    @Bindable private var theme = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            if KeychainStore.shared.hasValidCredentials() {
                authenticatedShell
            } else {
                WelcomeView()
            }
        }
        .onAppear {
            if KeychainStore.shared.hasValidCredentials() {
                Task {
                    await playerStore.connect()
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && KeychainStore.shared.hasValidCredentials() {
                Task {
                    await playerStore.connect()
                }
            }
        }
    }
    
    // MARK: - Authenticated Navigation Shell
    
    private var authenticatedShell: some View {
        ZStack(alignment: .bottom) {
            // Main Content Stage (State-preserving ZStack without native UITabBar collision)
            ZStack {
                HomeView()
                    .opacity(env.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(env.selectedTab == 0)

                SearchView()
                    .opacity(env.selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(env.selectedTab == 1)

                LibraryView()
                    .opacity(env.selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(env.selectedTab == 2)

                SettingsView()
                    .opacity(env.selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(env.selectedTab == 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            
            // Floating Liquid Glass Dock (MiniPlayer + Floating Glass Tab Bar)
            VStack(spacing: 6) {
                // Persistent Liquid Glass Mini Player (Screen S8)
                if playerStore.currentSnapshot != nil {
                    LiquidGlassMiniPlayer {
                        env.isNowPlayingPresented = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Custom Floating Liquid Glass Navigation Capsule
                customGlassTabBar
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
            }
            
            // Developer Telemetry HUD (Screen S11)
            if playerStore.isHUDOverlayVisible {
                DiagnosticOverlayHUD()
            }
        }
        .sheet(isPresented: $env.isNowPlayingPresented) {
            NowPlayingView()
        }
        .sheet(isPresented: $env.isLyricsPresented) {
            LyricsView()
        }
    }
    
    // MARK: - Custom Floating Liquid Glass Tab Bar
    
    private var customGlassTabBar: some View {
        HStack(spacing: 4) {
            tabItem(title: "Home", systemImage: "house.fill", tag: 0)
            tabItem(title: "Search", systemImage: "magnifyingglass", tag: 1)
            tabItem(title: "Library", systemImage: "books.vertical.fill", tag: 2)
            tabItem(title: "Settings", systemImage: "gearshape.fill", tag: 3)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(theme.currentPreset.glassTintColor)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.08),
                                    theme.specularRimColor.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
    }
    
    private func tabItem(title: String, systemImage: String, tag: Int) -> some View {
        let isSelected = env.selectedTab == tag
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                env.selectedTab = tag
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? theme.activeAccent : Color.white.opacity(0.45))
                    .frame(height: 18)
                
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule()
                        .fill(theme.activeAccent.opacity(0.18))
                        .overlay(
                            Capsule()
                                .stroke(theme.activeAccent.opacity(0.35), lineWidth: 0.8)
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
