//
//  CompositeLyricsRepository.swift
//  LineriOS
//
//  Five-stage lyrics orchestrator:
//  Stage 1 (SQLite Cache) -> Stage 2 (LRCLIB Exact) -> Stage 3 (LRCLIB Fuzzy)
//  -> Stage 4 (Plain-Text Fallback) -> Stage 5 (Local File Import).
//

import Foundation

public final class CompositeLyricsRepository: Sendable {
    public static let shared = CompositeLyricsRepository()

    private let cacheActor = SQLiteCacheActor.shared
    private let lrclibProvider = LRCLIBProvider.shared
    private let localFileProvider = LocalLRCFileProvider.shared

    public init() {}

    public func getOrFetchLyrics(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Int
    ) async throws -> LyricsPayload? {
        // Stage 1: SQLite WAL Cache (<1ms on-device lookup)
        if let cached = try await cacheActor.getLyrics(trackURI: trackURI) {
            RingBufferLogger.shared.log(
                level: .debug,
                category: "Lyrics",
                message: "Stage 1 Cache Hit for '\(title)' (\(cached.lines.count) lines, offset: \(cached.userOffsetMs)ms)"
            )
            return cached
        }

        // Stage 2 & 3: LRCLIB Network Fetch (Exact -> Fuzzy)
        RingBufferLogger.shared.log(
            level: .info,
            category: "Lyrics",
            message: "Stage 1 Cache Miss. Querying LRCLIB for '\(title)' by '\(artist)'..."
        )

        do {
            if let networkPayload = try await lrclibProvider.fetchLyrics(
                trackURI: trackURI,
                title: title,
                artist: artist,
                album: album,
                durationMs: durationMs
            ) {
                // Permanently store into SQLite WAL database
                try await cacheActor.saveLyrics(networkPayload)
                RingBufferLogger.shared.log(
                    level: .info,
                    category: "Lyrics",
                    message: "Cached \(networkPayload.lines.count) lines in SQLite for \(trackURI)"
                )
                return networkPayload
            }
        } catch {
            RingBufferLogger.shared.log(
                level: .warn,
                category: "Lyrics",
                message: "LRCLIB query failed: \(error.localizedDescription)"
            )
        }

        // Stage 4: Plain-Text Fallback
        return LyricsPayload(
            trackURI: trackURI,
            sourceProvider: "Fallback",
            granularity: .unavailable,
            lines: []
        )
    }

    public func updateUserOffset(trackURI: String, offsetMs: Int) async throws {
        try await cacheActor.updateUserOffset(trackURI: trackURI, offsetMs: offsetMs)
        RingBufferLogger.shared.log(
            level: .info,
            category: "Lyrics",
            message: "Updated user offset to \(offsetMs)ms for \(trackURI)"
        )
    }

    public func importLocalLyrics(content: String, trackURI: String) async throws -> LyricsPayload {
        let payload = localFileProvider.importFromText(content, trackURI: trackURI)
        try await cacheActor.saveLyrics(payload)
        return payload
    }
}
