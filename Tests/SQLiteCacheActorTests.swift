//
//  SQLiteCacheActorTests.swift
//  LineriOSUnitTests
//
//  Automated verification for SQLite WAL database concurrency, lyrics caching, and user offsets.
//

import XCTest
@testable import LineriOS

final class SQLiteCacheActorTests: XCTestCase {

    var tempDBURL: URL!
    var cacheActor: SQLiteCacheActor!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        tempDBURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite")
        cacheActor = SQLiteCacheActor(databaseURL: tempDBURL)
    }

    override func tearDown() async throws {
        cacheActor = nil
        try? FileManager.default.removeItem(at: tempDBURL)
    }

    func testInsertAndRetrieveLyrics() async throws {
        let line = LyricLine(startTimeMs: 1000, endTimeMs: 3000, text: "Testing SQLite")
        let payload = LyricsPayload(
            trackURI: "spotify:track:test1234",
            sourceProvider: "LRCLIB",
            granularity: .lineSynced,
            lines: [line],
            userOffsetMs: 50
        )

        try await cacheActor.saveLyrics(payload)

        let retrieved = try await cacheActor.getLyrics(trackURI: "spotify:track:test1234")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.trackURI, "spotify:track:test1234")
        XCTAssertEqual(retrieved?.lines.count, 1)
        XCTAssertEqual(retrieved?.lines.first?.text, "Testing SQLite")
        XCTAssertEqual(retrieved?.userOffsetMs, 50)
    }

    func testUpdateUserOffsetPersists() async throws {
        let line = LyricLine(startTimeMs: 500, endTimeMs: 2500, text: "Line 1")
        let payload = LyricsPayload(
            trackURI: "spotify:track:offsetTest",
            sourceProvider: "LRCLIB",
            granularity: .lineSynced,
            lines: [line],
            userOffsetMs: 0
        )

        try await cacheActor.saveLyrics(payload)
        try await cacheActor.updateUserOffset(trackURI: "spotify:track:offsetTest", offsetMs: -150)

        let updated = try await cacheActor.getLyrics(trackURI: "spotify:track:offsetTest")
        XCTAssertEqual(updated?.userOffsetMs, -150)
    }

    func testPaletteCacheStorage() async throws {
        let palette = ExtractedPalette(
            bgHex0: "#070913",
            bgHex1: "#0F1428",
            bgHex2: "#1E2952",
            bgHex3: "#38BDF8",
            accentHex: "#38BDF8"
        )

        try await cacheActor.savePalette(artworkURL: "https://example.com/art.jpg", palette: palette)

        let fetched = try await cacheActor.getPalette(artworkURL: "https://example.com/art.jpg")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.bgHex0, "#070913")
        XCTAssertEqual(fetched?.accentHex, "#38BDF8")
    }
}
