import Foundation

/// An sRGB color with separate values for light and dark mode, written as `0xRRGGBB`.
public struct SigningColor: Hashable, Sendable {
    /// The color used in light mode.
    public let light: UInt32
    /// The color used in dark mode.
    public let dark: UInt32

    /// One color for both modes.
    public init(hex: UInt32) {
        self.init(light: hex, dark: hex)
    }

    /// Different colors for light and dark mode.
    public init(light: UInt32, dark: UInt32) {
        self.light = light & 0xFFFFFF
        self.dark = dark & 0xFFFFFF
    }

    /// The Wthaiq brand blue `#121AB0`, with a lighter `#8B91F7` in dark mode so it stays readable on dark
    /// backgrounds (contrast 11.7:1 on white and 7.5:1 on black).
    public static let brand = SigningColor(light: 0x121AB0, dark: 0x8B91F7)

    static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
        (
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// WCAG 2 relative luminance.
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let rgb = components(hex)
        return 0.2126 * channel(rgb.red) + 0.7152 * channel(rgb.green) + 0.0722 * channel(rgb.blue)
    }

    /// WCAG 2 contrast ratio between two colors (1 to 21).
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let lumA = relativeLuminance(first)
        let lumB = relativeLuminance(second)
        return (max(lumA, lumB) + 0.05) / (min(lumA, lumB) + 0.05)
    }

    /// The text color drawn on top of `hex`: white when it reaches 4.5:1, otherwise near-black.
    static func foreground(on hex: UInt32) -> UInt32 {
        contrastRatio(hex, 0xFFFFFF) >= 4.5 ? 0xFFFFFF : 0x0B0B0B
    }
}
