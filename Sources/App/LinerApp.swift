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
                .environment(environment)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    environment.handleOpenURL(url)
                }
        }
    }
}

// MARK: - Root Lifecycle Stage View

struct RootLifecycleStageView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingAuthConfig: Bool = false
    
    var body: some View {
        ZStack {
            if KeychainStore.shared.hasValidCredentials() {
                authenticatedShell
            } else {
                WelcomeView(onConfigureTapped: {
                    showingAuthConfig = true
                })
            }
        }
        .sheet(isPresented: $showingAuthConfig) {
            AuthConfigView(
                onConfigSaved: {
                    // Refresh state once credentials are saved
                },
                onDismiss: {
                    showingAuthConfig = false
                }
            )
        }
    }
    
    // MARK: - Authenticated Navigation Shell
    
    private var authenticatedShell: some View {
        @Bindable var bindableEnv = env
        
        return ZStack(alignment: .bottom) {
            // Main Tab View
            TabView(selection: $bindableEnv.selectedTab) {
                HomeView(
                    themeManager: env.themeManager,
                    playerStore: env.playerStore,
                    libraryStore: env.libraryStore
                )
                .tag(AppEnvironment.TabIndex.home)
                
                SearchView(
                    themeManager: env.themeManager,
                    searchStore: env.searchStore,
                    playerStore: env.playerStore
                )
                .tag(AppEnvironment.TabIndex.search)
                
                LibraryView(
                    themeManager: env.themeManager,
                    libraryStore: env.libraryStore,
                    playerStore: env.playerStore
                )
                .tag(AppEnvironment.TabIndex.library)
                
                SettingsView(
                    themeManager: env.themeManager,
                    playerStore: env.playerStore,
                    lyricsStore: env.lyricsStore
                )
                .tag(AppEnvironment.TabIndex.settings)
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Floating Dock (MiniPlayer + Custom Glass Tab Bar)
            VStack(spacing: 8) {
                // Persistent Liquid Glass Mini Player (Screen S8)
                if env.playerStore.currentTrack != nil {
                    LiquidGlassMiniPlayer(
                        playerStore: env.playerStore,
                        themeManager: env.themeManager,
                        onExpandToNowPlaying: {
                            env.isNowPlayingPresented = true
                        },
                        onExpandToLyrics: {
                            env.isLyricsPresented = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Custom Floating Liquid Glass Navigation Bar
                customGlassTabBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            
            // Developer Telemetry HUD (Screen S11)
            if env.playerStore.isHUDOverlayVisible {
                DiagnosticOverlayHUD(
                    playerStore: env.playerStore,
                    themeManager: env.themeManager
                )
            }
        }
        .sheet(isPresented: $bindableEnv.isNowPlayingPresented) {
            NowPlayingView(
                playerStore: env.playerStore,
                themeManager: env.themeManager,
                onDismiss: {
                    env.isNowPlayingPresented = false
                },
                onOpenLyrics: {
                    env.isNowPlayingPresented = false
                    env.isLyricsPresented = true
                }
            )
        }
        .sheet(isPresented: $bindableEnv.isLyricsPresented) {
            LyricsView(
                lyricsStore: env.lyricsStore,
                playerStore: env.playerStore,
                themeManager: env.themeManager,
                onDismiss: {
                    env.isLyricsPresented = false
                }
            )
        }
    }
    
    // MARK: - Custom Glass Tab Bar
    
    private var customGlassTabBar: some View {
        HStack(spacing: 0) {
            tabItem(title: "Home", systemImage: "house.fill", tab: .home)
            tabItem(title: "Search", systemImage: "magnifyingglass", tab: .search)
            tabItem(title: "Library", systemImage: "books.vertical.fill", tab: .library)
            tabItem(title: "Settings", systemImage: "gearshape.fill", tab: .settings)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
    }
    
    private func tabItem(title: String, systemImage: String, tab: AppEnvironment.TabIndex) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                env.selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: env.selectedTab == tab ? .bold : .regular))
                    .foregroundStyle(env.selectedTab == tab ? env.themeManager.activeAccent : Color.white.opacity(0.5))
                
                Text(title)
                    .font(.system(size: 10, weight: env.selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(env.selectedTab == tab ? .white : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
