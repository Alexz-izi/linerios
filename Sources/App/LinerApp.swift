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
                    // Credentials updated in Keychain
                },
                onDismiss: {
                    showingAuthConfig = false
                }
            )
        }
    }
    
    // MARK: - Authenticated Navigation Shell
    
    private var authenticatedShell: some View {
        ZStack(alignment: .bottom) {
            // Main Tab View
            TabView(selection: $env.selectedTab) {
                HomeView()
                    .tag(0)
                
                SearchView()
                    .tag(1)
                
                LibraryView()
                    .tag(2)
                
                SettingsView()
                    .tag(3)
            }
            .ignoresSafeArea(edges: .bottom)
            
            // Floating Dock (MiniPlayer + Custom Glass Tab Bar)
            VStack(spacing: 8) {
                // Persistent Liquid Glass Mini Player (Screen S8)
                if playerStore.currentSnapshot != nil {
                    LiquidGlassMiniPlayer {
                        env.isNowPlayingPresented = true
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Custom Floating Liquid Glass Navigation Bar
                customGlassTabBar
                    .padding(.horizontal, 20)
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
    
    // MARK: - Custom Glass Tab Bar
    
    private var customGlassTabBar: some View {
        HStack(spacing: 0) {
            tabItem(title: "Home", systemImage: "house.fill", tag: 0)
            tabItem(title: "Search", systemImage: "magnifyingglass", tag: 1)
            tabItem(title: "Library", systemImage: "books.vertical.fill", tag: 2)
            tabItem(title: "Settings", systemImage: "gearshape.fill", tag: 3)
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
    
    private func tabItem(title: String, systemImage: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                env.selectedTab = tag
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: env.selectedTab == tag ? .bold : .regular))
                    .foregroundStyle(env.selectedTab == tag ? theme.activeAccent : Color.white.opacity(0.5))
                
                Text(title)
                    .font(.system(size: 10, weight: env.selectedTab == tag ? .semibold : .regular))
                    .foregroundStyle(env.selectedTab == tag ? .white : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
