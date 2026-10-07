#if os(iOS)
import UIKit

extension SigningColor {
    /// A dynamic `UIColor` that switches between `light` and `dark` with the interface style.
    public var uiColor: UIColor {
        let lightHex = light
        let darkHex = dark
        return UIColor { traits in
            SigningColor.makeColor(traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        }
    }

    /// Creates a color from a `UIColor`, resolving it once for light and once for dark mode.
    public init(_ color: UIColor) {
        let lightColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let darkColor = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        self.init(light: SigningColor.hex(of: lightColor), dark: SigningColor.hex(of: darkColor))
    }

    /// Readable text color for content drawn on top of this color.
    var foregroundUIColor: UIColor {
        let lightHex = SigningColor.foreground(on: light)
        let darkHex = SigningColor.foreground(on: dark)
        return UIColor { traits in
            SigningColor.makeColor(traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        }
    }

    static func makeColor(_ hex: UInt32) -> UIColor {
        let rgb = components(hex)
        return UIColor(red: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1)
    }

    static func hex(of color: UIColor) -> UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return SigningColor.brand.light
        }
        func byte(_ value: CGFloat) -> UInt32 {
            UInt32(min(max((value * 255).rounded(), 0), 255))
        }
        return (byte(red) << 16) | (byte(green) << 8) | byte(blue)
    }
}

extension WthaiqSigningConfiguration.InterfaceStyle {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
#endif
