//
//  PaletteExtractorProtocol.swift
//  LineriOS
//
//  Protocol contract for downsampling, k-means quantization, and WCAG AA contrast-clamped palettes.
//

import Foundation

public struct ExtractedPalette: Sendable, Codable, Equatable {
    public let bgHex0: String
    public let bgHex1: String
    public let bgHex2: String
    public let bgHex3: String
    public let accentHex: String
    public let extractedAt: Date

    public init(
        bgHex0: String,
        bgHex1: String,
        bgHex2: String,
        bgHex3: String,
        accentHex: String,
        extractedAt: Date = Date()
    ) {
        self.bgHex0 = bgHex0
        self.bgHex1 = bgHex1
        self.bgHex2 = bgHex2
        self.bgHex3 = bgHex3
        self.accentHex = accentHex
        self.extractedAt = extractedAt
    }
}

public protocol PaletteExtractorProtocol: Sendable {
    func extractPalette(fromImageData data: Data) async throws -> ExtractedPalette
}
