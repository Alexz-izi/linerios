//
//  LyricsProviderProtocol.swift
//  LineriOS
//
//  Protocol contract for synchronized lyrics providers (LRCLIB, Files import, Fallback).
//

import Foundation

public protocol LyricsProviderProtocol: Sendable {
    var providerName: String { get }
    func fetchLyrics(
        trackURI: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Int
    ) async throws -> LyricsPayload?
}
