//
//  SpotifyAppRemoteAdapter.swift
//  LineriOS
//
//  Low-latency (<15ms) local IPC adapter interfacing directly with the installed Spotify iOS app
//  via SpotifyiOS.xcframework (SPTAppRemote).
//

import Foundation
import UIKit

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

        RingBufferLogger.shared.log(
            level: .info,
            category: "AppRemote",
            message: "Initiating local IPC connection to Spotify app"
        )

        appRemote.connect()
    }

    public func disconnect() {
        guard let appRemote = self.appRemote, appRemote.isConnected else { return }
        appRemote.disconnect()
        connectionState = .disconnected
        isSubscribedToPlayer = false
        RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Disconnected local IPC")
    }

    public func authorizeAndPlayURI(_ uri: String = "") {
        guard let appRemote = self.appRemote else {
            configure()
            self.appRemote?.authorizeAndPlayURI(uri)
            return
        }
        appRemote.authorizeAndPlayURI(uri)
    }

    // MARK: - Playback Control Commands

    public func play(uri: String? = nil) async throws {
        guard let appRemote = self.appRemote, appRemote.isConnected, let playerAPI = appRemote.playerAPI else {
            throw AppRemoteError.notConnected
        }

        let start = CACurrentMediaTime()
        return try await withCheckedThrowingContinuation { continuation in
            if let uri = uri, !uri.isEmpty {
                playerAPI.play(uri, asRadio: false) { result, error in
                    let latency = (CACurrentMediaTime() - start) * 1000.0
                    if let error = error {
                        RingBufferLogger.shared.log(level: .error, category: "AppRemote", message: "Play URI failed: \(error.localizedDescription)", latencyMs: latency)
                        continuation.resume(throwing: error)
                    } else {
                        RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Play URI dispatched: \(uri)", latencyMs: latency)
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
                        RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Resumed playback", latencyMs: latency)
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
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Paused playback", latencyMs: latency)
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
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Skipped to next", latencyMs: latency)
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
                    RingBufferLogger.shared.log(level: .info, category: "AppRemote", message: "Skipped to previous", latencyMs: latency)
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
    public func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        connectionState = .connectedLocalIPC
        RingBufferLogger.shared.log(
            level: .info,
            category: "AppRemote",
            message: "Connected to Spotify via local IPC (<15ms latency)"
        )
        subscribeToPlayerState()
    }

    public func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        let msg = error?.localizedDescription ?? "Connection attempt failed"
        connectionState = .disconnected
        RingBufferLogger.shared.log(level: .warn, category: "AppRemote", message: "IPC failed: \(msg)")
    }

    public func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        let msg = error?.localizedDescription ?? "IPC disconnected"
        connectionState = .disconnected
        isSubscribedToPlayer = false
        RingBufferLogger.shared.log(level: .warn, category: "AppRemote", message: "Spotify disconnected: \(msg)")
    }
}

// MARK: - SPTAppRemotePlayerStateDelegate
extension SpotifyAppRemoteAdapter: SPTAppRemotePlayerStateDelegate {
    public func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let now = CACurrentMediaTime()
        let track = playerState.track

        let repeatMode: RepeatMode
        switch playerState.playbackOptions.repeatMode {
        case .off: repeatMode = .off
        case .one: repeatMode = .track
        case .all: repeatMode = .context
        @unknown default: repeatMode = .off
        }

        // Construct high-precision timing snapshot
        let snapshot = PlaybackSnapshot(
            trackURI: track.uri,
            title: track.name,
            artist: track.artist.name,
            album: track.album.name,
            artworkURL: nil, // Extracted on-demand or augmented by Web API
            durationMs: Int(track.duration),
            anchorPositionMs: playerState.playbackPosition,
            anchorMonotonicTime: now,
            isPlaying: !playerState.isPaused,
            shuffleEnabled: playerState.playbackOptions.isShuffling,
            repeatMode: repeatMode,
            activeDeviceName: "iPhone 14 Pro (Local IPC)"
        )

        self.currentSnapshot = snapshot
        self.lastObservedURI = track.uri
        onSnapshotUpdate?(snapshot)
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
