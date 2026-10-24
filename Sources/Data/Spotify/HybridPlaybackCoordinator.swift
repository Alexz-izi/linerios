//
//  HybridPlaybackCoordinator.swift
//  LineriOS
//
//  Three-stage playback orchestrator arbitrating between zero-latency local IPC (Stage 1),
//  cloud Spotify Connect REST polling (Stage 2), and URL-scheme wakeup (Stage 3).
//

import Foundation
import UIKit

@MainActor
public final class HybridPlaybackCoordinator: ObservableObject, PlaybackControllerProtocol {
    public static let shared = HybridPlaybackCoordinator()

    public private(set) var connectionState: PlaybackConnectionState = .disconnected
    public private(set) var currentSnapshot: PlaybackSnapshot?
    public var onSnapshotUpdate: ((PlaybackSnapshot) -> Void)?

    private let appRemoteAdapter = SpotifyAppRemoteAdapter.shared
    private let webApiClient = SpotifyWebAPIClient.shared

    private var connectPollingTask: Task<Void, Never>?
    private var lastObservedTrackURI: String?

    private init() {
        bindAdapter()
    }

    private func bindAdapter() {
        appRemoteAdapter.onSnapshotUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.currentSnapshot = snapshot
            self.lastObservedTrackURI = snapshot.trackURI
            self.onSnapshotUpdate?(snapshot)
        }

        appRemoteAdapter.onConnectionStateChange = { [weak self] state in
            guard let self = self else { return }
            self.handleIPCStateChange(state)
        }
    }

    // MARK: - PlaybackControllerProtocol

    public func connect() async throws {
        // Stage 1: Attempt local IPC socket connection
        connectionState = .connecting
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
        appRemoteAdapter.disconnect()
        connectionState = .disconnected
        currentSnapshot = nil
    }

    public func play(uri: String? = nil) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.play(uri: uri)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC play failed. Retrying via Web API.")
            }
        }

        // Cloud Web API Fallback
        do {
            try await webApiClient.play(uri: uri)
            await refreshCloudSnapshot()
        } catch {
            // Stage 3: Auto-wakeup via URL Scheme if background app is terminated
            tryWakeSpotifyApp(uri: uri)
            throw error
        }
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
        await refreshCloudSnapshot()
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
        try? await Task.sleep(for: .milliseconds(300))
        await refreshCloudSnapshot()
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
        try? await Task.sleep(for: .milliseconds(300))
        await refreshCloudSnapshot()
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
        try await webApiClient.seek(positionMs: positionMs)
        await refreshCloudSnapshot()
    }

    public func setShuffle(_ enabled: Bool) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.setShuffle(enabled)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC shuffle failed.")
            }
        }
        try await webApiClient.setShuffle(enabled: enabled)
        await refreshCloudSnapshot()
    }

    public func setRepeatMode(_ mode: RepeatMode) async throws {
        if connectionState == .connectedLocalIPC {
            do {
                try await appRemoteAdapter.setRepeatMode(mode)
                return
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Coordinator", message: "IPC repeat mode failed.")
            }
        }
        try await webApiClient.setRepeat(mode: mode)
        await refreshCloudSnapshot()
    }

    // MARK: - Stage Failover Management

    private func handleIPCStateChange(_ state: PlaybackConnectionState) {
        self.connectionState = state
        if state == .connectedLocalIPC {
            stopCloudPolling()
        } else if state == .disconnected {
            transitionToCloudConnect()
        }
    }

    private func transitionToCloudConnect() {
        guard connectPollingTask == nil else { return }
        connectionState = .connectedCloudWebAPI
        startCloudPolling()
    }

    private func startCloudPolling() {
        connectPollingTask?.cancel()
        connectPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.refreshCloudSnapshot()
                // Respect token bucket rate limits: poll every 5.0 seconds
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func stopCloudPolling() {
        connectPollingTask?.cancel()
        connectPollingTask = nil
    }

    private func refreshCloudSnapshot() async {
        do {
            if let snapshot = try await webApiClient.getPlaybackState() {
                self.currentSnapshot = snapshot
                self.lastObservedTrackURI = snapshot.trackURI
                self.onSnapshotUpdate?(snapshot)
            }
        } catch {
            if case WebAPIError.rateLimited(let sec) = error {
                self.connectionState = .rateLimited(retryAfter: sec)
            }
        }
    }

    private func tryWakeSpotifyApp(uri: String?) {
        let wakeTarget = uri ?? lastObservedTrackURI ?? ""
        let wakeURLString = wakeTarget.isEmpty ? "spotify:" : wakeTarget
        guard let url = URL(string: wakeURLString), UIApplication.shared.canOpenURL(url) else {
            return
        }

        RingBufferLogger.shared.log(
            level: .info,
            category: "Coordinator",
            message: "Stage 3 Auto-Wake: Launching Spotify background engine via \(wakeURLString)"
        )
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(800))
                    try? await self?.appRemoteAdapter.connect()
                }
            }
        }
    }
}
