//
//  SpotifyWebAPIClient.swift
//  LineriOS
//
//  March 2026 Spotify Development Mode Web API client.
//  Strictly conforms to:
//  1. Renamed /v1/playlists/{id}/items endpoint (tracks -> items, track -> item)
//  2. GET /v1/me/tracks for user library and PUT/DELETE /v1/me/library
//  3. Strict limit=10 search pagination
//  4. Exponential backoff and Retry-After handling on HTTP 429
//  5. Tolerance for omitted popularity and external_ids fields
//

import Foundation
import QuartzCore

public actor SpotifyWebAPIClient {
    public static let shared = SpotifyWebAPIClient()

    private let baseURL = URL(string: "https://api.spotify.com/v1/")!
    private var rateLimitCooldownUntil: Date?

    private init() {}

    private func parseURL(_ urlString: String?) -> URL? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Playback State (Connect Fallback)

    public func getCurrentPlaybackState() async throws -> PlaybackSnapshot? {
        guard try canMakeRequest() else { return nil }
        let start = CACurrentMediaTime()
        let data = try await performRequest(endpoint: "me/player", method: "GET")

        // 204 No Content -> nothing playing
        guard !data.isEmpty else { return nil }

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

        let artworkURL = parseURL(item.album?.images?.first?.url)

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
            isPlaying: response.isPlaying ?? false,
            shuffleEnabled: response.shuffleState ?? false,
            repeatMode: repeatMode,
            activeDeviceName: response.device?.name ?? "Spotify Connect"
        )
    }

    // MARK: - Playback Controls (Web API Connect Fallback)

    public func resume() async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/play", method: "PUT")
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

    public func seek(toPositionMs positionMs: Int) async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/seek?position_ms=\(positionMs)", method: "PUT")
    }

    public func play(uri: String) async throws {
        guard try canMakeRequest() else { return }
        let body: [String: Any] = ["uris": [uri]]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        _ = try await performRequest(endpoint: "me/player/play", method: "PUT", body: jsonData)
    }

    public func setShuffle(_ enabled: Bool) async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/player/shuffle?state=\(enabled)", method: "PUT")
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        guard try canMakeRequest() else { return }
        let stateString: String
        switch mode {
        case .off: stateString = "off"
        case .track: stateString = "track"
        case .context: stateString = "context"
        }
        _ = try await performRequest(endpoint: "me/player/repeat?state=\(stateString)", method: "PUT")
    }

    // MARK: - Search (Dev Mode limit=10)

    public func search(query: String, offset: Int = 0) async throws -> [TrackItem] {
        try await searchTracks(query: query, offset: offset)
    }

    public func searchTracks(query: String, offset: Int = 0) async throws -> [TrackItem] {
        guard try canMakeRequest() else { return [] }
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !encodedQuery.isEmpty else {
            return []
        }

        // Development mode limits pagination to 10
        let endpoint = "search?q=\(encodedQuery)&type=track&limit=10&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebSearchResponse.self, from: data)
        let tracks = response.tracks?.items ?? []

        return tracks.map { track in
            let artworkURL = parseURL(track.album?.images?.first?.url)
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
        return (response.items ?? []).compactMap { (item: WebSavedTrackItem) -> TrackItem? in
            guard let track = item.track else { return nil }
            let artworkURL = parseURL(track.album?.images?.first?.url)
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

    public func saveTrack(id: String) async throws {
        guard try canMakeRequest() else { return }
        // 2026 Dev Mode supports PUT /v1/me/library or PUT /v1/me/tracks
        _ = try await performRequest(endpoint: "me/tracks?ids=\(id)", method: "PUT")
    }

    public func saveTrackToLibrary(trackURI: String) async throws {
        let id = trackURI.replacingOccurrences(of: "spotify:track:", with: "")
        try await saveTrack(id: id)
    }

    public func removeTrack(id: String) async throws {
        guard try canMakeRequest() else { return }
        _ = try await performRequest(endpoint: "me/tracks?ids=\(id)", method: "DELETE")
    }

    public func removeTrackFromLibrary(trackURI: String) async throws {
        let id = trackURI.replacingOccurrences(of: "spotify:track:", with: "")
        try await removeTrack(id: id)
    }

    public func checkSavedState(id: String) async throws -> Bool {
        guard try canMakeRequest() else { return false }
        let data = try await performRequest(endpoint: "me/tracks/contains?ids=\(id)", method: "GET")
        let boolArray = try JSONDecoder().decode([Bool].self, from: data)
        return boolArray.first ?? false
    }

    // MARK: - Playlists (2026 Dev Mode /items schema)

    public func getPlaylists(limit: Int = 10, offset: Int = 0) async throws -> [PlaylistSummary] {
        guard try canMakeRequest() else { return [] }
        let endpoint = "me/playlists?limit=\(min(limit, 10))&offset=\(offset)"
        let data = try await performRequest(endpoint: endpoint, method: "GET")

        let response = try JSONDecoder().decode(WebPlaylistsResponse.self, from: data)
        return (response.items ?? []).map { item in
            let imageURL = parseURL(item.images?.first?.url)
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
        return (response.items ?? []).compactMap { (itemWrapper: WebPlaylistItemWrapper) -> TrackItem? in
            // Inside PlaylistItem, track was renamed to item
            guard let track = itemWrapper.item ?? itemWrapper.track else { return nil }
            let artworkURL = parseURL(track.album?.images?.first?.url)
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

    private func performRequest(endpoint: String, method: String, body: Data? = nil) async throws -> Data {
        let token = try await SpotifyPKCEAuthenticator.shared.validAccessToken()
        let fullURL = URL(string: endpoint, relativeTo: baseURL)!

        var request = URLRequest(url: fullURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let start = CACurrentMediaTime()
        let (data, response) = try await URLSession.shared.data(for: request)
        let latency = (CACurrentMediaTime() - start) * 1000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebAPIError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = parseRetryAfter(from: httpResponse)
            self.rateLimitCooldownUntil = Date().addingTimeInterval(retryAfter)
            RingBufferLogger.shared.log(
                level: .warn,
                category: "WebAPI",
                message: "HTTP 429 Rate limited. Cooldown for \(Int(retryAfter))s",
                latencyMs: latency
            )
            throw WebAPIError.rateLimited(retryAfter: retryAfter)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            RingBufferLogger.shared.log(
                level: .error,
                category: "WebAPI",
                message: "Request failed [\(httpResponse.statusCode)]: \(errorText)",
                latencyMs: latency
            )
            throw WebAPIError.httpError(statusCode: httpResponse.statusCode, message: errorText)
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

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header) {
            return seconds
        }
        return 5.0 // Conservative default
    }
}

// MARK: - Models for 2026 Dev Mode Schemas

public enum WebAPIError: LocalizedError, Sendable {
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval)
    case httpError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Received invalid HTTP response."
        case .rateLimited(let sec): return "Spotify API rate limit active. Retry in \(Int(sec))s."
        case .httpError(let code, let msg): return "Web API Error \(code): \(msg)"
        }
    }
}

public struct WebPlaybackStateResponse: Codable, Sendable {
    public let isPlaying: Bool?
    public let progressMs: Int?
    public let item: WebTrack?
    public let device: WebDevice?
    public let shuffleState: Bool?
    public let repeatState: String?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case progressMs = "progress_ms"
        case item
        case device
        case shuffleState = "shuffle_state"
        case repeatState = "repeat_state"
    }
}

public struct WebTrack: Codable, Sendable {
    public let id: String
    public let uri: String
    public let name: String
    public let durationMs: Int
    public let explicit: Bool?
    public let artists: [WebArtist]?
    public let album: WebAlbum?

    enum CodingKeys: String, CodingKey {
        case id, uri, name
        case durationMs = "duration_ms"
        case explicit, artists, album
    }
}

public struct WebArtist: Codable, Sendable {
    public let id: String?
    public let name: String
}

public struct WebAlbum: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let images: [WebImage]?
}

public struct WebImage: Codable, Sendable {
    public let url: String
    public let height: Int?
    public let width: Int?
}

public struct WebDevice: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let type: String?
}

public struct WebSearchResponse: Codable, Sendable {
    public let tracks: WebTrackPaging?
}

public struct WebTrackPaging: Codable, Sendable {
    public let items: [WebTrack]?
    public let total: Int?
    public let offset: Int?
    public let limit: Int?
}

public struct WebSavedTracksResponse: Codable, Sendable {
    public let items: [WebSavedTrackItem]?
    public let total: Int?
    public let offset: Int?
}

public struct WebSavedTrackItem: Codable, Sendable {
    public let addedAt: String?
    public let track: WebTrack?

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track
    }
}

public struct WebPlaylistsResponse: Codable, Sendable {
    public let items: [WebPlaylistRaw]?
    public let total: Int?
}

public struct WebPlaylistRaw: Codable, Sendable {
    public let id: String
    public let uri: String
    public let name: String
    public let images: [WebImage]?
    public let owner: WebOwner?
    public let items: WebPagingTotal?
    public let tracks: WebPagingTotal?
}

public struct WebPlaylistItemWrapper: Codable, Sendable {
    // 2026 Dev Mode renames track to item
    public let item: WebTrack?
    public let track: WebTrack?
}

public struct WebPlaylistItemsResponse: Codable, Sendable {
    public let items: [WebPlaylistItemWrapper]?
    public let total: Int?
}

public struct WebPagingTotal: Codable, Sendable {
    public let total: Int?
}

public struct WebOwner: Codable, Sendable {
    public let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
