//
//  PipelineProofTests.swift
//  LineriOSUnitTests
//
//  Automated verification for Milestone 0 pipeline proof and domain models.
//

import XCTest
@testable import LineriOS

final class PipelineProofTests: XCTestCase {

    func testThemePresetValues() {
        for preset in ThemePreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "Theme preset should have a non-empty display name")
            XCTAssertFalse(preset.id.isEmpty, "Theme preset should have a non-empty identifier")
        }
    }

    func testPlaybackSnapshotInitialization() {
        let snapshot = PlaybackSnapshot(
            trackURI: "spotify:track:test12345",
            title: "Test Track",
            artist: "Test Artist",
            album: "Test Album",
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            durationMs: 210000,
            anchorPositionMs: 45000,
            anchorMonotonicTime: 1234.56,
            isPlaying: true,
            shuffleEnabled: false,
            repeatMode: .off,
            activeDeviceName: "iPhone 14 Pro"
        )

        XCTAssertEqual(snapshot.trackURI, "spotify:track:test12345")
        XCTAssertEqual(snapshot.title, "Test Track")
        XCTAssertEqual(snapshot.durationMs, 210000)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.repeatMode, .off)
    }

    func testLyricsPayloadStructure() {
        let word1 = LyricWordToken(text: "Hello", startTimeMs: 1000, endTimeMs: 1500)
        let word2 = LyricWordToken(text: "Glass", startTimeMs: 1600, endTimeMs: 2200)
        let line = LyricLine(
            startTimeMs: 1000,
            endTimeMs: 2200,
            text: "Hello Glass",
            words: [word1, word2]
        )

        let payload = LyricsPayload(
            trackURI: "spotify:track:test12345",
            sourceProvider: "LRCLIB",
            granularity: .syllableSynced,
            lines: [line],
            userOffsetMs: 0
        )

        XCTAssertEqual(payload.sourceProvider, "LRCLIB")
        XCTAssertEqual(payload.granularity, .syllableSynced)
        XCTAssertEqual(payload.lines.count, 1)
        XCTAssertEqual(payload.lines.first?.words.count, 2)
        XCTAssertEqual(word1.progress(at: 1250), 0.5, accuracy: 0.01)
    }

    func testTrackItemFormattedDuration() {
        let item = TrackItem(
            id: "track_1",
            uri: "spotify:track:track_1",
            title: "Sample Song",
            artistName: "Sample Artist",
            albumName: "Sample Album",
            artworkURL: nil,
            durationMs: 215000 // 3 min 35 sec
        )

        XCTAssertEqual(item.formattedDuration, "3:35")
    }
}
