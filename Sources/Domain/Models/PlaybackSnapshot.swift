//
//  PlaybackSnapshot.swift
//  LineriOS
//
//  Domain model capturing instantaneous playback state and timing anchors.
//

import Foundation

public enum PlaybackConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connectedLocalIPC          // SPTAppRemote active (<15ms latency)
    case connectedCloudWebAPI       // Fallback HTTP Connect control
    case rateLimited(retryAfter: TimeInterval)
    case error(String)
}

public enum RepeatMode: String, Codable, Sendable, Equatable {
    case off
    case track
    case context
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public let trackURI: String
    public let title: String
    public let artist: String
    public let album: String
    public let artworkURL: URL?
    public let durationMs: Int
    public let anchorPositionMs: Int
    public let anchorMonotonicTime: TimeInterval // CACurrentMediaTime()
    public let isPlaying: Bool
    public let shuffleEnabled: Bool
    public let repeatMode: RepeatMode
    public let activeDeviceName: String

    public init(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        artworkURL: URL?,
        durationMs: Int,
        anchorPositionMs: Int,
        anchorMonotonicTime: TimeInterval,
        isPlaying: Bool,
        shuffleEnabled: Bool,
        repeatMode: RepeatMode,
        activeDeviceName: String
    ) {
        self.trackURI = trackURI
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.durationMs = durationMs
        self.anchorPositionMs = anchorPositionMs
        self.anchorMonotonicTime = anchorMonotonicTime
        self.isPlaying = isPlaying
        self.shuffleEnabled = shuffleEnabled
        self.repeatMode = repeatMode
        self.activeDeviceName = activeDeviceName
    }
}
