//
//  LRCLIBProvider.swift
//  LineriOS
//
//  Primary zero-cost synchronized lyrics adapter querying the open LRCLIB REST API (lrclib.net).
//  Implements exact GET /api/get matching and regex-normalized fuzzy search fallback.
//

import Foundation
import QuartzCore

public final class LRCLIBProvider: LyricsProviderProtocol, Sendable {
    public static let shared = LRCLIBProvider()

    public let providerName = "LRCLIB"
    private let baseURL = URL(string: "https://lrclib.net/api")!
    private let parser = BraccatoLyricsParser()

    public init() {}

    public func fetchLyrics(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Int
    ) async throws -> LyricsPayload? {
        let durationSeconds = max(1, durationMs / 1000)

        // Stage 2: Exact query /api/get
        if let exactResult = try await fetchExact(
            trackURI: trackURI,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds
        ) {
            return exactResult
        }

        // Stage 3: Fuzzy search /api/search fallback
        return try await fetchFuzzy(
            trackURI: trackURI,
            title: title,
            artist: artist,
            durationSeconds: durationSeconds
        )
    }

    // MARK: - Exact Query (/api/get)

    private func fetchExact(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        durationSeconds: Int
    ) async throws -> LyricsPayload? {
        var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: "\(durationSeconds)")
        ]

        guard let url = components.url else { return nil }

        let start = CACurrentMediaTime()
        guard let response = try await executeRequest(url: url) else { return nil }
        let latency = (CACurrentMediaTime() - start) * 1000.0

        RingBufferLogger.shared.log(
            level: .info,
            category: "LRCLIB",
            message: "Exact match found for '\(title)' by '\(artist)'",
            latencyMs: latency
        )

        return parseResponse(response, trackURI: trackURI)
    }

    // MARK: - Fuzzy Search (/api/search)

    private func fetchFuzzy(
        trackURI: String,
        title: String,
        artist: String,
        durationSeconds: Int
    ) async throws -> LyricsPayload? {
        // Strip parenthetical text like "(Remastered 2021)" or "[feat. X]"
        let cleanTitle = sanitizeTitle(title)
        let query = "\(cleanTitle) \(artist)"

        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components.url else { return nil }

        let start = CACurrentMediaTime()
        var request = URLRequest(url: url)
        request.setValue("LineriOS/1.0 (https://github.com/Alexz-izi/linerios)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        let latency = (CACurrentMediaTime() - start) * 1000.0

        guard let http = httpResponse as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let candidates = (try? JSONDecoder().decode([LRCLIBRecord].self, from: data)) ?? []
        guard !candidates.isEmpty else { return nil }

        // Find candidate closest to target duration (within 4 seconds tolerance)
        let bestCandidate = candidates.min { a, b in
            let diffA = abs((a.duration ?? 0) - Double(durationSeconds))
            let diffB = abs((b.duration ?? 0) - Double(durationSeconds))
            return diffA < diffB
        }

        guard let match = bestCandidate, abs((match.duration ?? 0) - Double(durationSeconds)) <= 5.0 else {
            return nil
        }

        RingBufferLogger.shared.log(
            level: .info,
            category: "LRCLIB",
            message: "Fuzzy match found for '\(title)' (diff: \(Int(abs((match.duration ?? 0) - Double(durationSeconds))))s)",
            latencyMs: latency
        )

        return parseResponse(match, trackURI: trackURI)
    }

    // MARK: - HTTP & Parsing Helpers

    private func executeRequest(url: URL) async throws -> LRCLIBRecord? {
        var request = URLRequest(url: url)
        request.setValue("LineriOS/1.0 (https://github.com/Alexz-izi/linerios)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }

        if http.statusCode == 404 {
            return nil // Normal cache miss
        }

        guard http.statusCode == 200 else {
            throw LRCLIBError.serverError(http.statusCode)
        }

        return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
    }

    private func parseResponse(_ record: LRCLIBRecord, trackURI: String) -> LyricsPayload {
        if record.instrumental == true {
            return LyricsPayload(
                trackURI: trackURI,
                sourceProvider: providerName,
                granularity: .instrumental,
                lines: [],
                plainTextFallback: "Instrumental"
            )
        }

        if let synced = record.syncedLyrics, !synced.isEmpty {
            return parser.parse(content: synced, trackURI: trackURI, provider: providerName)
        }

        if let plain = record.plainLyrics, !plain.isEmpty {
            return LyricsPayload(
                trackURI: trackURI,
                sourceProvider: providerName,
                granularity: .plainText,
                lines: [],
                plainTextFallback: plain
            )
        }

        return LyricsPayload(
            trackURI: trackURI,
            sourceProvider: providerName,
            granularity: .unavailable,
            lines: []
        )
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let pattern = #"\s*[\(\[][^\)\]]*(?:remaster|deluxe|version|feat|ft|explicit)[^\)\]]*[\)\]]"#
        let sanitized = raw.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        return sanitized.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - LRCLIB Models & Errors

private struct LRCLIBRecord: Codable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

public enum LRCLIBError: LocalizedError, Sendable {
    case serverError(Int)

    public var errorDescription: String? {
        switch self {
        case .serverError(let code): return "LRCLIB returned HTTP \(code)."
        }
    }
}
