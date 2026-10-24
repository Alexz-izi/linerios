//
//  LyricsPayload.swift
//  LineriOS
//
//  Domain models for synchronized lyrics, word tokens, and line models.
//

import Foundation

public enum LyricsSyncGranularity: String, Codable, Sendable, Equatable {
    case syllableSynced   // Enhanced LRC <mm:ss.xx> or TTML word spans
    case lineSynced       // Standard LRC [mm:ss.xx]
    case plainText        // Unsynchronized text
    case instrumental     // Explicit instrumental track
    case unavailable      // Not found
}

public struct LyricWordToken: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let startTimeMs: Int
    public let endTimeMs: Int

    public init(id: UUID = UUID(), text: String, startTimeMs: Int, endTimeMs: Int) {
        self.id = id
        self.text = text
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
    }

    /// Syllable progress fraction clamped to [0.0, 1.0] for time `currentTimeMs`
    public func progress(at currentTimeMs: Int) -> Double {
        guard endTimeMs > startTimeMs else {
            return currentTimeMs >= startTimeMs ? 1.0 : 0.0
        }
        let raw = Double(currentTimeMs - startTimeMs) / Double(endTimeMs - startTimeMs)
        return min(max(raw, 0.0), 1.0)
    }
}

public struct LyricLine: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let startTimeMs: Int
    public let endTimeMs: Int
    public let text: String
    public let words: [LyricWordToken] // Non-empty when syllableSynced

    public init(
        id: UUID = UUID(),
        startTimeMs: Int,
        endTimeMs: Int,
        text: String,
        words: [LyricWordToken] = []
    ) {
        self.id = id
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.text = text
        self.words = words
    }
}

public struct LyricsPayload: Codable, Sendable, Equatable {
    public let trackURI: String
    public let sourceProvider: String
    public let granularity: LyricsSyncGranularity
    public let lines: [LyricLine]
    public let plainTextFallback: String?
    public let userOffsetMs: Int
    public let fetchedAt: Date

    public init(
        trackURI: String,
        sourceProvider: String,
        granularity: LyricsSyncGranularity,
        lines: [LyricLine],
        plainTextFallback: String? = nil,
        userOffsetMs: Int = 0,
        fetchedAt: Date = Date()
    ) {
        self.trackURI = trackURI
        self.sourceProvider = sourceProvider
        self.granularity = granularity
        self.lines = lines
        self.plainTextFallback = plainTextFallback
        self.userOffsetMs = userOffsetMs
        self.fetchedAt = fetchedAt
    }
}
