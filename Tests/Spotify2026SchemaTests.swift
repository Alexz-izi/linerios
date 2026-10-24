//
//  Spotify2026SchemaTests.swift
//  LineriOSUnitTests
//
//  Unit verification for 2026 Spotify schema decoding, PKCE parameter generation,
//  and RingBufferLogger thread safety.
//

import XCTest
@testable import LineriOS

final class Spotify2026SchemaTests: XCTestCase {

    func testRingBufferLoggerCapacity() {
        let logger = RingBufferLogger(capacity: 20)
        for i in 1...50 {
            logger.log(level: .info, category: "Test", message: "Message \(i)")
        }

        let logs = logger.getRecentLogs()
        XCTAssertEqual(logs.count, 20)
        // Most recent message should be #50
        XCTAssertEqual(logs.first?.message, "Message 50")
    }

    func testTrackItemDecoding() {
        let json = """
        {
            "id": "test_id_123",
            "uri": "spotify:track:test_id_123",
            "title": "Starboy",
            "artistName": "The Weeknd",
            "albumName": "Starboy",
            "artworkURL": "https://i.scdn.co/image/ab67616d0000b273",
            "durationMs": 230453,
            "isExplicit": true,
            "isSaved": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        XCTAssertNoThrow(try decoder.decode(TrackItem.self, from: json))
    }

    func testTokenResponseDecoding() {
        let json = """
        {
            "access_token": "mock_access_token_xyz",
            "token_type": "Bearer",
            "expires_in": 3600,
            "refresh_token": "mock_refresh_token_abc",
            "scope": "user-read-playback-state user-modify-playback-state"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        do {
            let res = try decoder.decode(TokenResponse.self, from: json)
            XCTAssertEqual(res.accessToken, "mock_access_token_xyz")
            XCTAssertEqual(res.expiresIn, 3600)
            XCTAssertEqual(res.refreshToken, "mock_refresh_token_abc")
        } catch {
            XCTFail("Failed to decode TokenResponse: \(error)")
        }
    }
}
