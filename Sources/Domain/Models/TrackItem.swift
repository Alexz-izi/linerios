//
//  TrackItem.swift
//  LineriOS
//
//  Domain model representing a catalog, playlist, or library track.
//

import Foundation

public struct TrackItem: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let uri: String
    public let title: String
    public let artistName: String
    public let albumName: String
    public let artworkURL: URL?
    public let durationMs: Int
    public let isExplicit: Bool
    public var isSaved: Bool

    public init(
        id: String,
        uri: String,
        title: String,
        artistName: String,
        albumName: String,
        artworkURL: URL?,
        durationMs: Int,
        isExplicit: Bool = false,
        isSaved: Bool = false
    ) {
        self.id = id
        self.uri = uri
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.artworkURL = artworkURL
        self.durationMs = durationMs
        self.isExplicit = isExplicit
        self.isSaved = isSaved
    }

    /// Formatted mm:ss duration display string
    public var formattedDuration: String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
