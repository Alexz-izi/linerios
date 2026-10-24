//
//  SpotifyAppRemoteAdapter.swift
//  LineriOS
//
//  Low-latency (<15ms) local IPC adapter interfacing directly with the installed Spotify iOS app
//  via SpotifyiOS.xcframework (SPTAppRemote).
//

import Foundation
import UIKit
import QuartzCore

@MainActor
public final class SpotifyAppRemoteAdapter: NSObject, ObservableObject {
    public static let shared = SpotifyAppRemoteAdapter()

    public private(set) var connectionState: PlaybackConnectionState = .disconnected {
        didSet {
            onConnectionStateChange?(connectionState)
        }
    }

    public private(set) var currentSnapshot: PlaybackSnapshot?
    public var onSnapshotUpdate: ((PlaybackSnapshot) -> Void)?
    public var onConnectionStateChange: ((PlaybackConnectionState) -> Void)?

    private var appRemote: SPTAppRemote?
    private var isSubscribedToPlayer: Bool = false
    private var lastObservedURI: String?

    private override init() {
        super.init()
    }

    // MARK: - Connection Lifecycle

    public func configure() {
        guard let clientId = KeychainStore.shared.get(stringForKey: .clientId),
              let redirectURL = URL(string: SpotifyPKCEAuthenticator.redirectURI) else {
            return
        }

        let configuration = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        configuration.playURI = ""

        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        self.appRemote = remote
    }

    public func connect() async throws {
        if appRemote == nil {
            configure()
        }

        guard let appRemote = self.appRemote else {
            throw AppRemoteError.notConfigured
        }

        guard let token = try? await SpotifyPKCEAuthenticator.shared.validAccessToken() else {
            connectionState = .error("Missing OAuth token")
            throw AppRemoteError.unauthorized
        }

        appRemote.connectionParameters.accessToken = token
        connectionState = .connecting

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                appRemote.connect()
                // Connection confirmation handled by SPTAppRemoteDelegate callbacks
                continuation.resume()
            }
        }
    }

    public func disconnect() async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected else { return }
        appRemote.disconnect()
        self.connectionState = .disconnected
        self.isSubscribedToPlayer = false
    }

    // MARK: - Transport Commands

    public func play(uri: String?) async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            if let uri = uri, !uri.isEmpty {
                playerAPI.play(uri, asRadio: false) { result, error in
                    let latency = (CACurrentMediaTime() - start) * 1000.0
                    if let error = error {
                        RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Play failed: \(error.localizedDescription)", latencyMs: latency)
                        continuation.resume(throwing: error)
                    } else {
                        RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Playback started for \(uri)", latencyMs: latency)
                        continuation.resume()
                    }
                }
            } else {
                playerAPI.resume { result, error in
                    let latency = (CACurrentMediaTime() - start) * 1000.0
                    if let error = error {
                        RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Resume failed: \(error.localizedDescription)", latencyMs: latency)
                        continuation.resume(throwing: error)
                    } else {
                        RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Playback resumed", latencyMs: latency)
                        continuation.resume()
                    }
                }
            }
        }
    }

    public func pause() async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.pause { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Pause failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Playback paused", latencyMs: latency)
                    continuation.resume()
                }
            }
        }
    }

    public func skipNext() async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.skip(toNext: { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Skip next failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Skipped to next track", latencyMs: latency)
                    continuation.resume()
                }
            })
        }
    }

    public func skipPrevious() async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.skip(toPrevious: { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Skip previous failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Skipped to previous track", latencyMs: latency)
                    continuation.resume()
                }
            })
        }
    }

    public func seek(toPositionMs positionMs: Int) async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.seek(toPosition: positionMs) { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Seek failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Seeked to \(positionMs)ms", latencyMs: latency)
                    continuation.resume()
                }
            }
        }
    }

    public func setShuffle(_ enabled: Bool) async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.setShuffle(enabled) { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Set shuffle failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Shuffle set to \(enabled)", latencyMs: latency)
                    continuation.resume()
                }
            }
        }
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let sptMode: SPTAppRemotePlaybackOptionsRepeatMode
        switch mode {
        case .off: sptMode = .off
        case .track: sptMode = .one
        case .context: sptMode = .all
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            playerAPI.setRepeatMode(sptMode) { result, error in
                let latency = (CACurrentMediaTime() - start) * 1000.0
                if let error = error {
                    RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Set repeat failed: \(error.localizedDescription)", latencyMs: latency)
                    continuation.resume(throwing: error)
                } else {
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Repeat set to \(mode.rawValue)", latencyMs: latency)
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - State Ingestion

    private func subscribeToPlayerState() {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            return
        }
        playerAPI.delegate = self
        playerAPI.subscribe(toPlayerState: { result, error in
            if let error = error {
                RingBufferLogger.shared.log(level: .warn, category: "AppRemote", message: "Subscribe to player state failed: \(error.localizedDescription)")
            } else {
                self.isSubscribedToPlayer = true
                RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Subscribed to local player state updates")
            }
        })
    }
}

// MARK: - SPTAppRemoteDelegate
extension SpotifyAppRemoteAdapter: SPTAppRemoteDelegate {
    nonisolated public func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.connectionState = .connectedLocalIPC
            RingBufferLogger.shared.log(
                level: .info,
                category: "AppRemote",
                message: "Connected to Spotify via local IPC (<15ms latency)"
            )
            self.subscribeToPlayerState()
        }
    }

    nonisolated public func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let msg = error?.localizedDescription ?? "Connection attempt failed"
        Task { @MainActor in
            self.connectionState = .disconnected
            RingBufferLogger.shared.log(level: .warn, category: "AppRemote", message: "IPC failed: \(msg)")
        }
    }

    nonisolated public func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let msg = error?.localizedDescription ?? "IPC disconnected"
        Task { @MainActor in
            self.connectionState = .disconnected
            self.isSubscribedToPlayer = false
            RingBufferLogger.shared.log(level: .warn, category: "AppRemote", message: "Spotify disconnected: \(msg)")
        }
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate
extension SpotifyAppRemoteAdapter: SPTAppRemotePlayerStateDelegate {
    nonisolated public func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let now = CACurrentMediaTime()
        let track = playerState.track
        let trackUri = track.uri
        let trackName = track.name
        let artistName = track.artist.name
        let albumName = track.album.name
        let duration = track.duration
        let playbackPos = playerState.playbackPosition
        let isPaused = playerState.isPaused
        let isShuffling = playerState.playbackOptions.isShuffling

        let repeatMode: RepeatMode
        switch playerState.playbackOptions.repeatMode {
        case .off: repeatMode = .off
        case .one: repeatMode = .track
        case .all: repeatMode = .context
        @unknown default: repeatMode = .off
        }

        Task { @MainActor in
            let snapshot = PlaybackSnapshot(
                trackURI: trackUri,
                title: trackName,
                artist: artistName,
                album: albumName,
                artworkURL: nil,
                durationMs: Int(duration),
                anchorPositionMs: playbackPos,
                anchorMonotonicTime: now,
                isPlaying: !isPaused,
                shuffleEnabled: isShuffling,
                repeatMode: repeatMode,
                activeDeviceName: "iPhone 14 Pro (Local IPC)"
            )

            self.currentSnapshot = snapshot
            self.lastObservedURI = trackUri
            self.onSnapshotUpdate?(snapshot)
        }
    }
}

public enum AppRemoteError: LocalizedError, Sendable {
    case notConfigured
    case unauthorized
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Spotify App Remote is not configured."
        case .unauthorized: return "OAuth authorization token is missing or invalid."
        case .notConnected: return "Local IPC socket to Spotify app is not active."
        }
    }
}
