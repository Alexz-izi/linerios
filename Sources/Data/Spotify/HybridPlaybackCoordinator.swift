//
//  HybridPlaybackCoordinator.swift
//  LineriOS
//
//  3-stage failover playback coordinator bridging:
//  Stage 1: SPTAppRemote local IPC socket (<15ms latency)
//  Stage 2: Spotify Web API Connect REST fallback (100-300ms latency)
//  Stage 3: spotify:app-remote URL scheme local app wake-up
//

import Foundation
import UIKit
import QuartzCore

@MainActor
public final class HybridPlaybackCoordinator: PlaybackControllerProtocol {
    public static let shared = HybridPlaybackCoordinator()

    public private(set) var connectionState: PlaybackConnectionState = .disconnected {
        didSet {
            RingBufferLogger.shared.log(
                level: .info,
                category: "Coordinator",
                message: "Playback connection state: \(connectionState)"
            )
        }
    }

    public private(set) var currentSnapshot: PlaybackSnapshot?
    public var onSnapshotUpdate: ((PlaybackSnapshot) -> Void)?

    private let appRemoteAdapter: SpotifyAppRemoteAdapter
    private let webApiClient: SpotifyWebAPIClient
    private let clock: ClockInterpolator

    private var pollingTask: Task<Void, Never>?
    private var lastObservedPositionMs: Int = 0

    public init(
        appRemoteAdapter: SpotifyAppRemoteAdapter = SpotifyAppRemoteAdapter.shared,
        webApiClient: SpotifyWebAPIClient = SpotifyWebAPIClient.shared,
        clock: ClockInterpolator = ClockInterpolator.shared
    ) {
        self.appRemoteAdapter = appRemoteAdapter
        self.webApiClient = webApiClient
        self.clock = clock

        bindAppRemote()
    }

    // MARK: - PlaybackControllerProtocol: Connection Lifecycle

    public func connect() async throws {
        connectionState = .connecting

        // Stage 1: Attempt local IPC connection to installed Spotify app
        do {
            try await appRemoteAdapter.connect()
            // Success -> state becomes .connectedLocalIPC via delegate callback
        } catch {
            RingBufferLogger.shared.log(
                level: .warn,
                category: "Coordinator",
                message: "Stage 1 IPC failed (\(error.localizedDescription)). Transitioning to Stage 2 Cloud Connect."
            )
            // Stage 2: Fall back to Web API Connect monitoring
            transitionToCloudConnect()
        }
    }

    public func disconnect() {
        stopCloudPolling()
        Task {
            try? await appRemoteAdapter.disconnect()
        }
        connectionState = .disconnected
        currentSnapshot = nil
    }

    public func play(uri: String? = nil) async throws {
        // Stage 1: Fast local IPC socket if active and connected
        if connectionState == .connectedLocalIPC, let remote = appRemoteAdapter.appRemote, remote.isConnected {
            do {
                try await appRemoteAdapter.play(uri: uri)
                return
            } catch {
                RingBufferLogger.shared.log(
                    level: .warn,
                    category: "Coordinator",
                    message: "IPC play failed (\(error.localizedDescription)). Transitioning to Web API / App Remote wake."
                )
            }
        }

        // Stage 2: Spotify Web API Connect if an active session exists
        var webAPISucceeded = false
        do {
            if let uri = uri, !uri.isEmpty {
                try await webApiClient.play(uri: uri)
            } else {
                try await webApiClient.resume()
            }
            webAPISucceeded = true

            // Immediately poll for current state to synchronize UI
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if let snapshot = try? await self.webApiClient.getCurrentPlaybackState() {
                    await MainActor.run {
                        self.currentSnapshot = snapshot
                        self.onSnapshotUpdate?(snapshot)
                        self.clock.updateAnchor(
                            positionMs: snapshot.anchorPositionMs,
                            monotonicTime: snapshot.anchorMonotonicTime,
                            isPlaying: snapshot.isPlaying
                        )
                    }
                }
            }
        } catch {
            RingBufferLogger.shared.log(
                level: .warn,
                category: "Coordinator",
                message: "Web API play failed (\(error.localizedDescription)). Invoking Stage 3 Spotify App Remote wake."
            )
        }

        if webAPISucceeded {
            return
        }

        // Stage 3: Direct Spotify App Remote Wake & Handshake
        await wakeAndPlay(uri: uri)
    }

    public func pause() async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.pause()
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC pause failed. Retrying via Web API.")
            }
        }
        try await webApiClient.pause()
    }

    public func skipNext() async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.skipNext()
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC skip next failed. Retrying via Web API.")
            }
        }
        try await webApiClient.skipNext()
    }

    public func skipPrevious() async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.skipPrevious()
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC skip previous failed. Retrying via Web API.")
            }
        }
        try await webApiClient.skipPrevious()
    }

    public func seek(toPositionMs positionMs: Int) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.seek(toPositionMs: positionMs)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC seek failed. Retrying via Web API.")
            }
        }
        try await webApiClient.seek(toPositionMs: positionMs)
    }

    public func setShuffle(_ enabled: Bool) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.setShuffle(enabled)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC shuffle failed. Retrying via Web API.")
            }
        }
        try await webApiClient.setShuffle(enabled)
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.setRepeatMode(mode)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC repeat mode failed. Retrying via Web API.")
            }
        }
        try await webApiClient.setRepeatMode(mode)
    }

    // MARK: - Stage 3: Local App Wake-up

    public func wakeSpotifyApp() {
        appRemoteAdapter.authorizeAndPlayURI("")
    }

    public func wakeAndPlay(uri: String?) async {
        await MainActor.run {
            let trackURI = uri ?? ""
            appRemoteAdapter.authorizeAndPlayURI(trackURI)
        }
    }

    // MARK: - Bindings & Internal Synchronization

    private func bindAppRemote() {
        appRemoteAdapter.onConnectionStateChange = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            if state == .connectedLocalIPC {
                self.stopCloudPolling()
            } else if state == .disconnected {
                self.transitionToCloudConnect()
            }
        }

        appRemoteAdapter.onSnapshotUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.currentSnapshot = snapshot
            self.onSnapshotUpdate?(snapshot)

            // Update CADisplayLink monotonic clock anchor
            self.clock.updateAnchor(
                positionMs: snapshot.anchorPositionMs,
                monotonicTime: snapshot.anchorMonotonicTime,
                isPlaying: snapshot.isPlaying
            )
        }
    }

    private func transitionToCloudConnect() {
        connectionState = .connectedCloudWebAPI
        startCloudPolling()
    }

    private func startCloudPolling() {
        stopCloudPolling()
        pollingTask = Task { [weak self] in
            // Immediate first check
            if let self = self {
                if let snapshot = try? await self.webApiClient.getCurrentPlaybackState() {
                    await MainActor.run {
                        self.currentSnapshot = snapshot
                        self.onSnapshotUpdate?(snapshot)
                        self.clock.updateAnchor(
                            positionMs: snapshot.anchorPositionMs,
                            monotonicTime: snapshot.anchorMonotonicTime,
                            isPlaying: snapshot.isPlaying
                        )
                    }
                }
            }

            while !Task.isCancelled {
                // Poll every 3 seconds while in Cloud Connect fallback mode
                try? await Task.sleep(for: .seconds(3))
                guard let self = self else { break }
                do {
                    if let snapshot = try await self.webApiClient.getCurrentPlaybackState() {
                        await MainActor.run {
                            self.currentSnapshot = snapshot
                            self.onSnapshotUpdate?(snapshot)
                            self.clock.updateAnchor(
                                positionMs: snapshot.anchorPositionMs,
                                monotonicTime: snapshot.anchorMonotonicTime,
                                isPlaying: snapshot.isPlaying
                            )
                        }
                    }
                } catch {
                    if case WebAPIError.rateLimited(let retryAfter) = error {
                        await MainActor.run {
                            self.connectionState = .rateLimited(retryAfter: retryAfter)
                        }
                        try? await Task.sleep(for: .seconds(retryAfter))
                    }
                }
            }
        }
    }

    private func stopCloudPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
