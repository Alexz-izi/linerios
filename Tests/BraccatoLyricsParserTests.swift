//
//  BraccatoLyricsParserTests.swift
//  LineriOSUnitTests
//
//  Automated verification for LRC, Enhanced LRC syllable timestamps, and TTML parsing.
//

import XCTest
@testable import LineriOS

final class BraccatoLyricsParserTests: XCTestCase {

    func testStandardLRCLineParsing() {
        let lrc = """
        [00:12.34]First line of lyrics
        [00:15.80]Second line of lyrics
        [00:20.00]Third line of lyrics
        """

        let parser = BraccatoLyricsParser()
        let payload = parser.parse(content: lrc, trackURI: "spotify:track:test")

        XCTAssertEqual(payload.granularity, .lineSynced)
        XCTAssertEqual(payload.lines.count, 3)
        XCTAssertEqual(payload.lines[0].startTimeMs, 12340)
        XCTAssertEqual(payload.lines[0].text, "First line of lyrics")
        XCTAssertEqual(payload.lines[1].startTimeMs, 15800)
    }

    func testEnhancedLRCSyllables() {
        let enhancedLrc = """
        [00:05.10] <00:05.10> Hel <00:05.60> lo <00:06.00> world
        """

        let parser = BraccatoLyricsParser()
        let payload = parser.parse(content: enhancedLrc, trackURI: "spotify:track:test")

        XCTAssertEqual(payload.granularity, .syllableSynced)
        XCTAssertEqual(payload.lines.count, 1)
        let firstLine = payload.lines[0]
        XCTAssertEqual(firstLine.words.count, 3)
        XCTAssertEqual(firstLine.words[0].text.trimmingCharacters(in: .whitespaces), "Hel")
        XCTAssertEqual(firstLine.words[0].startTimeMs, 5100)
        XCTAssertEqual(firstLine.words[1].startTimeMs, 5600)
    }

    func testInstrumentalDetection() {
        let instrumentalText = "[au: Instrumental]"
        let parser = BraccatoLyricsParser()
        let payload = parser.parse(content: instrumentalText, trackURI: "spotify:track:test")

        XCTAssertEqual(payload.granularity, .instrumental)
        XCTAssertTrue(payload.lines.isEmpty)
    }
}
