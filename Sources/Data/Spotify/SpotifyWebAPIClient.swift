//
//  SpotifyWebAPIClient.swift
//  LineriOS
//
//  REST client strictly compliant with March 2026 Development Mode specifications:
//  /v1/playlists/{id}/items schema, limit=10 pagination caps, PUT/DELETE /v1/me/library endpoints,
//  and token-bucket rate limit (HTTP 429) backoff arbitration.
//

import Foundation
import QuartzCore

public actor SpotifyWebAPIClient {
    public static let shared = SpotifyWebAPIClient()

    private let baseURL = URL(string: "https://api.spotify.com/v1")!
    private var rateLimitCooldownUntil: Date?

    private init() {}

    // MARK: - Playback State & Control (Connect Fallback)

    public func getPlaybackState() async throws -> PlaybackSnapshot? {
        guard try canMakeRequest() else { return nil }

        let start = CACurrentMediaTime()
        let data: Data
        do {
            data = try await performRequest(endpoint: "me/player", method: "GET")
        } catch WebAPIError.noContent {
            return nil
        }
        let latency = (CACurrentMediaTime() - start) * 1000.0

        let response = try JSONDecoder().decode(WebPlaybackStateResponse.self, from: data)
        guard let item = response.item else { return nil }

        let now = CACurrentMediaTime()
        let repeatMode: RepeatMode
        switch response.repeatState {
        case "track": repeatMode = .track
        case "context": repeatMode = .context
        default: repeatMode = .off
        }

        let artworkURL = item.album?.images?.first?.url.flatMap { URL(string: $0) }

        RingBufferLogger.shared.log(
            level: .debug,
            category: "WebAPI",
            message: "Fetched playback state via Connect",
            latencyMs: latency
        )

        return PlaybackSnapshot(
            trackURI: item.uri,
            title: item.name,
            artist: item.artists?.map(\.name).joined(separator: ", ") ?? "Unknown Artist",
            album: item.album?.name ?? "Unknown Album",
            artworkURL: artworkURL,
            durationMs: item.durationMs,
            anchorPositionMs: response.progressMs ?? 0,
            anchorMonotonicTime: now,
            isPlaying: response.isPlaying,
            shuffleEnabled: response.shuffleState,
            repeatMode: repeatMode,
            activeDeviceName: response.device?.name ?? "Cloud Connect"
        )
    }

    public func play(uri: String? = nil, contextUri: String? = nil) async throws {
        guard try canMakeRequest() else { return }

        var body: [String: Any] = [:]
        if let uri = uri, !uri.isEmpty {
            body["uris"] = [uri]
        } else if let context = contextUri, !context.isEmpty {
            body["context_uri"] = context
        }

        let bodyData = body.isEmpty ? nil : try JSONSerialization.data(withJSONObject: body)
        _ = try await performRequest(endpoint: "me/player/play", method: "PUT", body: bodyData)
    }

    public func pause() async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/pause", method: "PUT")
    }

    public func skipNext() async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/next", method: "POST")
    }

    public func skipPrevious() async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/previous", method: "POST")
    }

    public func seek(positionMs: Int) async throws {
        guard try canMakeRequest() else { return }
        let endpoint = "me/player/seek?position_ms=\(positionMs)"
        _ = try await performRequest(endpoint: endpoint, method: "PUT")
    }

    public func setShuffle(enabled: Bool) async throws {
        guard try canMakeRequest() else { return }
        let endpoint = "me/player/shuffle?state=\(enabled)"
        _ = try await performRequest(endpoint: endpoint, method: "PUT")
    }

    public func setRepeat(mode: RepeatMode) async throws {
        guard try canMakeRequest() else { return }
        let stateStr: String
        switch mode {
        case .off: stateStr = "off"
        case .track: stateStr = "track"
        case .context: stateStr = "context"
        }
        let endpoint = "me/player/repeat?state=\(stateStr)"
        _ = try await performRequest(endpoint: endpoint, method: "PUT")
    }

    // MARK: - Search & Catalog (Limit=10 Capped)

    public func search(query: String, offset: Int = 0) async throws -> [TrackItem] {
        guard try canMakeRequest() else { return [] }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        // Limit strictly capped at 10 per 2026 Development Mode rules
        let endpoint = "search?q=\(encodedQuery)&type=track&limit=10&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebSearchResponse.self, from: data)
        let tracks = response.tracks?.items ?? []

        return tracks.map { track in
            let artworkURL = track.album?.images?.first?.url.flatMap { URL(string: $0) }
            return TrackItem(
                id: track.id,
                uri: track.uri,
                title: track.name,
                artistName: track.artists?.map(\.name).joined(separator: ", ") ?? "Unknown Artist",
                albumName: track.album?.name ?? "Unknown Album",
                artworkURL: artworkURL,
                durationMs: track.durationMs,
                isExplicit: track.explicit ?? false,
                isSaved: false
            )
        }
    }

    // MARK: - Library & Saved Tracks

    public func getSavedTracks(limit: Int = 10, offset: Int = 0) async throws -> [TrackItem] {
        guard try canMakeRequest() else { return [] }
        let safeLimit = min(max(1, limit), 10) // 10 max in Dev Mode
        let endpoint = "me/tracks?limit=\(safeLimit)&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebSavedTracksResponse.self, from: data)
        return (response.items ?? []).compactMap { item in
            guard let track = item.track else { return nil }
            let artworkURL = track.album?.images?.first?.url.flatMap { URL(string: $0) }
            return TrackItem(
                id: track.id,
                uri: track.uri,
                title: track.name,
                artistName: track.artists?.map(\.name).joined(separator: ", ") ?? "Unknown Artist",
                albumName: track.album?.name ?? "Unknown Album",
                artworkURL: artworkURL,
                durationMs: track.durationMs,
                isExplicit: track.explicit ?? false,
                isSaved: true
            )
        }
    }

    public func saveTrackToLibrary(trackURI: String) async throws {
        guard try canMakeRequest() else { return }
        guard let encoded = trackURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let endpoint = "me/library?uris=\(encoded)"
        _ = try await performRequest(endpoint: endpoint, method: "PUT")
        RingBufferLogger.shared.log(level: .info, category: "WebAPI", message: "Saved track to library: \(trackURI)")
    }

    public func removeTrackFromLibrary(trackURI: String) async throws {
        guard try canMakeRequest() else { return }
        guard let encoded = trackURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let endpoint = "me/library?uris=\(encoded)"
        _ = try await performRequest(endpoint: endpoint, method: "DELETE")
        RingBufferLogger.shared.log(level: .info, category: "WebAPI", message: "Removed track from library: \(trackURI)")
    }

    // MARK: - Playlists (2026 /items Schema)

    public func getPlaylists(limit: Int = 10, offset: Int = 0) async throws -> [PlaylistSummary] {
        guard try canMakeRequest() else { return [] }
        let endpoint = "me/playlists?limit=\(min(limit, 10))&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebPlaylistsResponse.self, from: data)
        return (response.items ?? []).map { item in
            let imageURL = item.images?.first?.url.flatMap { URL(string: $0) }
            return PlaylistSummary(
                id: item.id,
                uri: item.uri,
                name: item.name,
                ownerName: item.owner?.displayName ?? "Spotify",
                totalItems: item.items?.total ?? item.tracks?.total ?? 0,
                imageURL: imageURL
            )
        }
    }

    public func getPlaylistItems(playlistId: String, offset: Int = 0) async throws -> [TrackItem] {
        guard try canMakeRequest() else { return [] }
        // 2026 Dev Mode renamed /v1/playlists/{id}/tracks -> /v1/playlists/{id}/items
        let endpoint = "playlists/\(playlistId)/items?limit=10&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebPlaylistItemsResponse.self, from: data)
        return (response.items ?? []).compactMap { itemWrapper in
            // Inside PlaylistItem, track was renamed to item
            guard let track = itemWrapper.item ?? itemWrapper.track else { return nil }
            let artworkURL = track.album?.images?.first?.url.flatMap { URL(string: $0) }
            return TrackItem(
                id: track.id,
                uri: track.uri,
                title: track.name,
                artistName: track.artists?.map(\.name).joined(separator: ", ") ?? "Unknown Artist",
                albumName: track.album?.name ?? "Unknown Album",
                artworkURL: artworkURL,
                durationMs: track.durationMs,
                isExplicit: track.explicit ?? false,
                isSaved: false
            )
        }
    }

    // MARK: - Core HTTP Request Engine

    private func performRequest(
        endpoint: String,
        method: String,
        body: Data? = nil
    ) async throws -> Data {
        let token = try await SpotifyPKCEAuthenticator.shared.validAccessToken()
        let url = URL(string: endpoint, relativeTo: baseURL)!

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let start = CACurrentMediaTime()
        let (data, response) = try await URLSession.shared.data(for: request)
        let latency = (CACurrentMediaTime() - start) * 1000.0

        guard let http = response as? HTTPURLResponse else {
            throw WebAPIError.invalidResponse
        }

        if http.statusCode == 429 {
            let retryAfterSeconds = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) } ?? 5.0
            rateLimitCooldownUntil = Date().addingTimeInterval(retryAfterSeconds)
            RingBufferLogger.shared.log(
                level: .warn,
                category: "WebAPI",
                message: "Rate limited (429). Cooldown: \(retryAfterSeconds)s",
                latencyMs: latency
            )
            throw WebAPIError.rateLimited(retryAfter: retryAfterSeconds)
        }

        if http.statusCode == 204 {
            // No Content (successful Play/Pause/Seek)
            return Data()
        }

        guard (200...299).contains(http.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            RingBufferLogger.shared.log(
                level: .error,
                category: "WebAPI",
                message: "Request failed: \(method) \(endpoint) -> \(http.statusCode)",
                latencyMs: latency
            )
            throw WebAPIError.httpError(statusCode: http.statusCode, message: errorText)
        }

        return data
    }

    private func canMakeRequest() throws -> Bool {
        if let cooldown = rateLimitCooldownUntil {
            if Date() < cooldown {
                let remaining = cooldown.timeIntervalSinceNow
                throw WebAPIError.rateLimited(retryAfter: remaining)
            } else {
                rateLimitCooldownUntil = nil
            }
        }
        return true
    }
}

// MARK: - Supporting Models & Response Schemas

public struct PlaylistSummary: Sendable, Identifiable, Equatable {
    public let id: String
    public let uri: String
    public let name: String
    public let ownerName: String
    public let totalItems: Int
    public let imageURL: URL?
}

public enum WebAPIError: LocalizedError, Sendable {
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval)
    case httpError(statusCode: Int, message: String)
    case noContent

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Received invalid HTTP response."
        case .rateLimited(let sec): return "Spotify API rate limit active. Retry after \(Int(sec))s."
        case .httpError(let code, let msg): return "Spotify API error (\(code)): \(msg)"
        case .noContent: return "No content available."
        }
    }
}

// MARK: - Decodable Payload Envelopes
private struct WebPlaybackStateResponse: Decodable {
    let isPlaying: Bool
    let progressMs: Int?
    let shuffleState: Bool
    let repeatState: String
    let item: WebTrack?
    let device: WebDevice?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case shuffleState = "shuffle_state"
        case repeatState = "repeat_state"
        case item
        case device
    }
}

private struct WebDevice: Decodable {
    let name: String
}

private struct WebTrack: Decodable {
    let id: String
    let uri: String
    let name: String
    let durationMs: Int
    let explicit: Bool?
    let artists: [WebArtist]?
    let album: WebAlbum?

    enum CodingKeys: String, CodingKey {
        case id, uri, name, artists, album
        case durationMs = "duration_ms"
        case explicit
    }
}

private struct WebArtist: Decodable {
    let name: String
}

private struct WebAlbum: Decodable {
    let name: String
    let images: [WebImage]?
}

private struct WebImage: Decodable {
    let url: String
}

private struct WebSearchResponse: Decodable {
    let tracks: WebTrackPaging?
}

private struct WebTrackPaging: Decodable {
    let items: [WebTrack]?
    let total: Int?
}

private struct WebSavedTracksResponse: Decodable {
    let items: [WebSavedTrackItem]?
}

private struct WebSavedTrackItem: Decodable {
    let track: WebTrack?
}

private struct WebPlaylistsResponse: Decodable {
    let items: [WebPlaylistRaw]?
}

private struct WebPlaylistRaw: Decodable {
    let id: String
    let uri: String
    let name: String
    let owner: WebOwner?
    let images: [WebImage]?
    let items: WebPagingTotal?
    let tracks: WebPagingTotal?
}

private struct WebOwner: Decodable {
    let displayName: String?
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct WebPagingTotal: Decodable {
    let total: Int?
}

private struct WebPlaylistItemsResponse: Decodable {
    let items: [WebPlaylistItemWrapper]?
}

private struct WebPlaylistItemWrapper: Decodable {
    let item: WebTrack?
    let track: WebTrack?
}
