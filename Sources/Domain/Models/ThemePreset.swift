//
//  ThemePreset.swift
//  LineriOS
//
//  Liquid Glass design tokens and 4 immutable theme presets.
//

import SwiftUI

public enum ThemePreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case goth       // Default: Stark Black & White Goth
    case midnight   // Deep Navy / Sky Cyan
    case obsidian   // Pure OLED Stealth
    case aurora     // Nordic Emerald
    case afterhours // Warm Synth Rose

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .goth:       return "Goth (B&W)"
        case .midnight:   return "Midnight"
        case .obsidian:   return "Obsidian"
        case .aurora:     return "Aurora"
        case .afterhours: return "Afterhours"
        }
    }

    public var name: String { displayName }

    public var bgPrimary: Color {
        switch self {
        case .goth:       return Color(hex: "#000000")
        case .midnight:   return Color(hex: "#070913")
        case .obsidian:   return Color(hex: "#000000")
        case .aurora:     return Color(hex: "#06110E")
        case .afterhours: return Color(hex: "#11080A")
        }
    }

    public var bgSecondary: Color {
        switch self {
        case .goth:       return Color(hex: "#0A0A0A")
        case .midnight:   return Color(hex: "#0F1428")
        case .obsidian:   return Color(hex: "#0A0A0C")
        case .aurora:     return Color(hex: "#0D211B")
        case .afterhours: return Color(hex: "#1F0E13")
        }
    }

    public var glassTintColor: Color {
        switch self {
        case .goth:       return Color(hex: "#FFFFFF").opacity(0.06)
        case .midnight:   return Color(hex: "#1E2952").opacity(0.24)
        case .obsidian:   return Color(hex: "#FFFFFF").opacity(0.08)
        case .aurora:     return Color(hex: "#10B981").opacity(0.18)
        case .afterhours: return Color(hex: "#F43F5E").opacity(0.20)
        }
    }

    public var specularRimColor: Color {
        switch self {
        case .goth:       return Color(hex: "#FFFFFF").opacity(0.35)
        case .midnight:   return Color(hex: "#7DD3FC").opacity(0.32)
        case .obsidian:   return Color(hex: "#E2E8F0").opacity(0.40)
        case .aurora:     return Color(hex: "#6EE7B7").opacity(0.35)
        case .afterhours: return Color(hex: "#FDA4AF").opacity(0.36)
        }
    }

    public var accentPrimary: Color {
        switch self {
        case .goth:       return Color(hex: "#FFFFFF") // Stark White
        case .midnight:   return Color(hex: "#38BDF8") // Sky Cyan
        case .obsidian:   return Color(hex: "#F8FAFC") // Crisp Silver
        case .aurora:     return Color(hex: "#34D399") // Emerald
        case .afterhours: return Color(hex: "#FB7185") // Neon Rose
        }
    }

    public var accent: Color { accentPrimary }

    public var meshNode2: Color {
        switch self {
        case .goth:       return Color(hex: "#161616") // Deep Charcoal
        case .midnight:   return Color(hex: "#4F46E5") // Indigo
        case .obsidian:   return Color(hex: "#18181B") // Zinc Dark
        case .aurora:     return Color(hex: "#8B5CF6") // Violet
        case .afterhours: return Color(hex: "#D97706") // Warm Amber
        }
    }

    public var textPrimary: Color {
        switch self {
        case .goth:       return Color(hex: "#FFFFFF")
        case .midnight:   return Color(hex: "#F8FAFC")
        case .obsidian:   return Color(hex: "#FFFFFF")
        case .aurora:     return Color(hex: "#ECFDF5")
        case .afterhours: return Color(hex: "#FFF1F2")
        }
    }

    public var textMuted: Color {
        switch self {
        case .goth:       return Color(hex: "#888888")
        case .midnight:   return Color(hex: "#94A3B8").opacity(0.34)
        case .obsidian:   return Color(hex: "#71717A").opacity(0.36)
        case .aurora:     return Color(hex: "#6EE7B7").opacity(0.32)
        case .afterhours: return Color(hex: "#FDA4AF").opacity(0.34)
        }
    }
}

// MARK: - Hex Color Extension
extension Color {
    public init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
