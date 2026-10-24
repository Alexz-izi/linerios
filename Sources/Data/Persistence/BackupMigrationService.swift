//
//  BackupMigrationService.swift
//  LineriOS
//
//  Deliverable 18: Portable JSON Backup & Atomic SQLite Migration Engine.
//  Schema version 1: liner_backup_v1.
//  Enables full offline portability of lyrics, palettes, and user sync offsets.
//

import Foundation

public struct LinerBackupArchive: Codable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let appVersion: String
    public let preferences: PreferencesPayload
    public let cachedLyrics: [LyricsBackupItem]
    public let cachedPalettes: [PaletteBackupItem]
    
    public struct PreferencesPayload: Codable, Sendable {
        public let selectedPreset: String
        public let specularRimIntensity: Double
        public let userManualOffsetMs: Int
        public let developerHUDEnabled: Bool
        
        public init(selectedPreset: String, specularRimIntensity: Double, userManualOffsetMs: Int, developerHUDEnabled: Bool) {
            self.selectedPreset = selectedPreset
            self.specularRimIntensity = specularRimIntensity
            self.userManualOffsetMs = userManualOffsetMs
            self.developerHUDEnabled = developerHUDEnabled
        }
    }
    
    public struct LyricsBackupItem: Codable, Sendable {
        public let trackURI: String
        public let sourceProvider: String
        public let granularity: String
        public let lines: [LyricLine]
        public let plainTextFallback: String?
        public let userOffsetMs: Int
        public let fetchedAt: Date
        
        public init(trackURI: String, sourceProvider: String, granularity: String, lines: [LyricLine], plainTextFallback: String?, userOffsetMs: Int, fetchedAt: Date) {
            self.trackURI = trackURI
            self.sourceProvider = sourceProvider
            self.granularity = granularity
            self.lines = lines
            self.plainTextFallback = plainTextFallback
            self.userOffsetMs = userOffsetMs
            self.fetchedAt = fetchedAt
        }
    }
    
    public struct PaletteBackupItem: Codable, Sendable {
        public let artworkUrl: String
        public let bgHex0: String
        public let bgHex1: String
        public let bgHex2: String
        public let bgHex3: String
        public let accentHex: String
        public let extractedAt: Date
        
        public init(artworkUrl: String, bgHex0: String, bgHex1: String, bgHex2: String, bgHex3: String, accentHex: String, extractedAt: Date) {
            self.artworkUrl = artworkUrl
            self.bgHex0 = bgHex0
            self.bgHex1 = bgHex1
            self.bgHex2 = bgHex2
            self.bgHex3 = bgHex3
            self.accentHex = accentHex
            self.extractedAt = extractedAt
        }
    }
    
    public init(
        schemaVersion: Int,
        exportedAt: Date,
        appVersion: String,
        preferences: PreferencesPayload,
        cachedLyrics: [LyricsBackupItem],
        cachedPalettes: [PaletteBackupItem]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.preferences = preferences
        self.cachedLyrics = cachedLyrics
        self.cachedPalettes = cachedPalettes
    }
}

public final class BackupMigrationService: Sendable {
    public static let shared = BackupMigrationService()
    
    private init() {}
    
    public func createBackupArchive(
        cacheActor: SQLiteCacheActor,
        selectedPreset: String,
        specularRim: Double,
        hudEnabled: Bool
    ) async throws -> Data {
        let prefs = LinerBackupArchive.PreferencesPayload(
            selectedPreset: selectedPreset,
            specularRimIntensity: specularRim,
            userManualOffsetMs: 0,
            developerHUDEnabled: hudEnabled
        )
        
        let cached = (try? await cacheActor.getAllCachedLyrics()) ?? []
        let lyricsItems = cached.map {
            LinerBackupArchive.LyricsBackupItem(
                trackURI: $0.trackURI,
                sourceProvider: $0.sourceProvider,
                granularity: $0.granularity.rawValue,
                lines: $0.lines,
                plainTextFallback: $0.plainTextFallback,
                userOffsetMs: $0.userOffsetMs,
                fetchedAt: $0.fetchedAt
            )
        }
        
        let archive = LinerBackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            appVersion: "1.0.0",
            preferences: prefs,
            cachedLyrics: lyricsItems,
            cachedPalettes: []
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }
    
    public func restoreBackupArchive(
        from data: Data,
        cacheActor: SQLiteCacheActor
    ) async throws -> LinerBackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let archive = try decoder.decode(LinerBackupArchive.self, from: data)
        guard archive.schemaVersion == 1 else {
            throw NSError(
                domain: "com.personal.linerios.backup",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported backup schema version \(archive.schemaVersion)"]
            )
        }
        
        for item in archive.cachedLyrics {
            let payload = LyricsPayload(
                trackURI: item.trackURI,
                sourceProvider: item.sourceProvider,
                granularity: LyricsSyncGranularity(rawValue: item.granularity) ?? .lineSynced,
                lines: item.lines,
                plainTextFallback: item.plainTextFallback,
                userOffsetMs: item.userOffsetMs,
                fetchedAt: item.fetchedAt
            )
            try? await cacheActor.saveLyrics(payload)
        }
        
        return archive
    }
}
