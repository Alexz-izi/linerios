//
//  PlaybackControllerProtocol.swift
//  LineriOS
//
//  Protocol contract decoupling playback controllers (App Remote IPC & Web API) from UI.
//

import Foundation

@MainActor
public protocol PlaybackControllerProtocol: AnyObject {
    var connectionState: PlaybackConnectionState { get }
    var currentSnapshot: PlaybackSnapshot? { get }
    var onSnapshotUpdate: ((PlaybackSnapshot) -> Void)? { get set }

    func connect() async throws
    func disconnect()
    func play(uri: String?) async throws
    func pause() async throws
    func skipNext() async throws
    func skipPrevious() async throws
    func seek(toPositionMs: Int) async throws
    func setShuffle(_ enabled: Bool) async throws
    func setRepeatMode(_ mode: RepeatMode) async throws
}
