//
//  LocalLRCFileProvider.swift
//  LineriOS
//
//  Stage 5 local file and clipboard importer for .lrc and .ttml synced lyrics files.
//  Bypasses network completely, allowing user-supplied lyrics to be stored permanently in SQLite.
//

import Foundation

public final class LocalLRCFileProvider: LyricsProviderProtocol, Sendable {
    public static let shared = LocalLRCFileProvider()

    public let providerName = "LocalFile"
    private let parser = BraccatoLyricsParser()

    public init() {}

    public func fetchLyrics(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Int
    ) async throws -> LyricsPayload? {
        // Files are user-imported on demand rather than queried automatically by metadata
        return nil
    }

    public func importFromText(_ content: String, trackURI: String) -> LyricsPayload {
        let payload = parser.parse(content: content, trackURI: trackURI, provider: providerName)
        RingBufferLogger.shared.log(
            level: .info,
            category: "Lyrics",
            message: "Imported \(payload.lines.count) lines from text for \(trackURI)"
        )
        return payload
    }

    public func importFromFile(at url: URL, trackURI: String) throws -> LyricsPayload {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let content = try String(contentsOf: url, encoding: .utf8)
        let payload = parser.parse(content: content, trackURI: trackURI, provider: "LocalFile: \(url.lastPathComponent)")

        RingBufferLogger.shared.log(
            level: .info,
            category: "Lyrics",
            message: "Imported file '\(url.lastPathComponent)' (\(payload.lines.count) lines)"
        )
        return payload
    }
}
