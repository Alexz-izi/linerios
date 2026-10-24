//
//  SettingsView.swift
//  LineriOS
//
//  Screen S11: Application Settings, SideStore 7-Day Certificate Health,
//  SQLite Cache Storage Management, Developer HUD Toggle, and Backup Import/Export.
//

import SwiftUI
import UniformTypeIdentifiers

public struct SettingsView: View {
    @Bindable var themeManager: ThemeManager
    let playerStore: PlayerStore
    let lyricsStore: LyricsStore
    
    @State private var showingCustomizer = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var backupData: Data?
    @State private var statusMessage: String?
    
    @State private var lyricsCount: Int = 0
    @State private var paletteCount: Int = 0
    @State private var databaseBytes: Int64 = 0
    
    public init(themeManager: ThemeManager, playerStore: PlayerStore, lyricsStore: LyricsStore) {
        self.themeManager = themeManager
        self.playerStore = playerStore
        self.lyricsStore = lyricsStore
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AdaptiveAtmosphereMeshView(themeManager: themeManager)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        sideStoreCertificateCard
                        appearanceCard
                        cacheManagementCard
                        backupCard
                        developerCard
                        accountCard
                        
                        if let msg = statusMessage {
                            Text(msg)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(themeManager.activeAccent)
                                .padding()
                                .background(Color.black.opacity(0.4))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCustomizer) {
                ThemeCustomizerView(themeManager: themeManager)
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .task {
                await loadCacheStatistics()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var sideStoreCertificateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
                Text("SIDESTORE REFRESH STATUS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Active")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Text("Free Apple Developer accounts require on-device sideload refresh every 7 days. SideStore manages background renewal through LocalDevVPN.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            
            Button {
                if let url = URL(string: "sidestore://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Open SideStore to Refresh")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            
            Button {
                showingCustomizer = true
            } label: {
                HStack {
                    Circle()
                        .fill(themeManager.activeAccent)
                        .frame(width: 20, height: 20)
                    Text("Preset: \(themeManager.selectedPreset.name)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(14)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var cacheManagementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OFFLINE STORAGE (SQLITE WAL)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lyricsCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Cached Tracks")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(paletteCount)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Cached Palettes")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBytes(databaseBytes))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Database Size")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    Task {
                        await lyricsStore.clearLocalCache()
                        await loadCacheStatistics()
                        statusMessage = "Lyrics cache cleared"
                    }
                } label: {
                    Text("Clear Lyrics")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                Button {
                    Task {
                        await SQLiteCacheActor.shared.clearPaletteCache()
                        await loadCacheStatistics()
                        statusMessage = "Palette cache cleared"
                    }
                } label: {
                    Text("Clear Palettes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DATA BACKUP & RESTORATION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            
            Text("Export cached lyrics, manual syllable offsets, and palette archives to a portable JSON backup file.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            
            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            let data = try await BackupMigrationService.shared.createBackupArchive(
                                cacheActor: SQLiteCacheActor.shared,
                                selectedPreset: themeManager.selectedPreset.name,
                                specularRim: themeManager.specularRimIntensity,
                                hudEnabled: playerStore.isHUDOverlayVisible
                            )
                            self.backupData = data
                            self.showingExportSheet = true
                            statusMessage = "Backup generated (\(data.count) bytes)"
                        } catch {
                            statusMessage = "Export failed: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Backup")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                Button {
                    showingImportPicker = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Backup")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DIAGNOSTICS & TELEMETRY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            
            Toggle(isOn: Binding(
                get: { playerStore.isHUDOverlayVisible },
                set: { playerStore.isHUDOverlayVisible = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer Telemetry HUD")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Overlays 120Hz CADisplayLink FPS, Mach memory, and IPC socket metrics.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .tint(themeManager.activeAccent)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SPOTIFY CREDENTIALS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            
            Button {
                playerStore.disconnectAndClearCredentials()
                statusMessage = "Spotify disconnected"
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Disconnect & Clear Hardware Keychain")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(glassCardBackground)
    }
    
    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
    
    // MARK: - Helpers
    
    private func loadCacheStatistics() async {
        let stats = await SQLiteCacheActor.shared.getCacheStatistics()
        self.lyricsCount = stats.lyricsCount
        self.paletteCount = stats.paletteCount
        self.databaseBytes = stats.databaseSizeBytes
    }
    
    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                let data = try Data(contentsOf: url)
                Task {
                    let archive = try await BackupMigrationService.shared.restoreBackupArchive(
                        from: data,
                        cacheActor: SQLiteCacheActor.shared
                    )
                    await loadCacheStatistics()
                    statusMessage = "Restored backup successfully (\(archive.cachedLyrics.count) lyrics)"
                }
            } catch {
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            statusMessage = "Picker failed: \(error.localizedDescription)"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
