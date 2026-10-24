//
//  ThemeManager.swift
//  LineriOS
//
//  MainActor observable manager governing theme presets, dynamic album atmosphere blending,
//  and WCAG AA contrast preservation.
//

import SwiftUI
import Observation

@MainActor
@Observable
public final class ThemeManager {
    public static let shared = ThemeManager()

    public var currentPreset: ThemePreset = .goth {
        didSet {
            UserDefaults.standard.set(currentPreset.rawValue, forKey: "liner_selected_theme")
        }
    }

    public var selectedPreset: ThemePreset {
        get { currentPreset }
        set { currentPreset = newValue }
    }

    public var specularRimIntensity: Double = 0.25
    public var extractedPalette: ExtractedPalette?
    public var useAdaptiveAtmosphere: Bool = true

    private let extractor = VImagePaletteExtractor.shared
    private let cacheActor = SQLiteCacheActor.shared
    private var lastExtractedURLString: String?

    public init() {
        if let saved = UserDefaults.standard.string(forKey: "liner_selected_theme"),
           let preset = ThemePreset(rawValue: saved) {
            self.currentPreset = preset
        }
    }

    public func selectPreset(_ preset: ThemePreset) {
        self.currentPreset = preset
    }

    // MARK: - Dynamic Palette Resolution

    public func updateArtwork(url: URL?) {
        guard let url = url, useAdaptiveAtmosphere else {
            extractedPalette = nil
            return
        }

        let urlString = url.absoluteString
        guard urlString != lastExtractedURLString else { return }
        self.lastExtractedURLString = urlString

        Task {
            // Check SQLite palette cache first (<1ms)
            if let cached = try? await cacheActor.getPalette(artworkURL: urlString) {
                self.extractedPalette = cached
                return
            }

            // Download & extract palette on background thread
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let palette = try await extractor.extractPalette(fromImageData: data)
                try? await cacheActor.savePalette(artworkURL: urlString, palette: palette)
                self.extractedPalette = palette
            } catch {
                RingBufferLogger.shared.log(level: .warn, category: "Theme", message: "Palette extraction skipped: \(error.localizedDescription)")
            }
        }
    }

    public func extractDynamicPalette(from url: URL) async {
        updateArtwork(url: url)
    }

    // MARK: - Active Mesh Color Tokens

    public var bgPrimary: Color {
        currentPreset.bgPrimary
    }

    public var bgSecondary: Color {
        currentPreset.bgSecondary
    }

    public var meshColor0: Color {
        if let pal = extractedPalette, useAdaptiveAtmosphere {
            return Color(hex: pal.bgHex0)
        }
        return currentPreset.bgPrimary
    }

    public var meshColor1: Color {
        if let pal = extractedPalette, useAdaptiveAtmosphere {
            return Color(hex: pal.bgHex1)
        }
        return currentPreset.bgSecondary
    }

    public var meshColor2: Color {
        if let pal = extractedPalette, useAdaptiveAtmosphere {
            return Color(hex: pal.bgHex2)
        }
        return currentPreset.meshNode2
    }

    public var meshColor3: Color {
        if let pal = extractedPalette, useAdaptiveAtmosphere {
            return Color(hex: pal.bgHex3)
        }
        return currentPreset.bgPrimary
    }

    public var activeAccent: Color {
        if let pal = extractedPalette, useAdaptiveAtmosphere {
            return Color(hex: pal.accentHex)
        }
        return currentPreset.accentPrimary
    }

    public var specularRimColor: Color {
        currentPreset.specularRimColor
    }

    public var textPrimary: Color {
        currentPreset.textPrimary
    }

    public var textMuted: Color {
        currentPreset.textMuted
    }
}
