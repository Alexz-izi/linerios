//
//  BackupMigrationTests.swift
//  LineriOSTests
//
//  Unit tests for LinerBackupArchive v1 JSON serialization and deserialization.
//

import XCTest
@testable import LineriOS

final class BackupMigrationTests: XCTestCase {
    
    func testBackupArchiveSerialization() throws {
        let prefs = LinerBackupArchive.PreferencesPayload(
            selectedPreset: "Midnight",
            specularRimIntensity: 0.25,
            userManualOffsetMs: -100,
            developerHUDEnabled: true
        )
        
        let archive = LinerBackupArchive(
            schemaVersion: 1,
            exportedAt: Date(),
            appVersion: "1.0.0",
            preferences: prefs,
            cachedLyrics: [],
            cachedPalettes: []
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LinerBackupArchive.self, from: data)
        
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.preferences.selectedPreset, "Midnight")
        XCTAssertEqual(decoded.preferences.specularRimIntensity, 0.25, accuracy: 0.001)
        XCTAssertEqual(decoded.preferences.userManualOffsetMs, -100)
        XCTAssertTrue(decoded.preferences.developerHUDEnabled)
    }
}
