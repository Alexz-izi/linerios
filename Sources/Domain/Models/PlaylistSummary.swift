//
//  PlaylistSummary.swift
//  LineriOS
//
//  Domain model representing a Spotify playlist summary.
//

import Foundation

public struct PlaylistSummary: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let uri: String
    public let name: String
    public let ownerName: String
    public let totalItems: Int
    public let imageURL: URL?

    public init(
        id: String,
        uri: String,
        name: String,
        ownerName: String,
        totalItems: Int,
        imageURL: URL?
    ) {
        self.id = id
        self.uri = uri
        self.name = name
        self.ownerName = ownerName
        self.totalItems = totalItems
        self.imageURL = imageURL
    }
}
