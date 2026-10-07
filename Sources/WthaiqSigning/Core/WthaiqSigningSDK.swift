import Foundation

/// Version information for the Wthaiq signing SDK.
public enum WthaiqSigningSDK {
    /// The SDK version (Semantic Versioning).
    public static let version = "1.0.0"

    /// The Wthaiq API version this release was built against.
    public static let apiVersion = "2026-07-01"

    /// The hosts that serve Wthaiq signing pages. Add your custom signing domain to
    /// `WthaiqSigningConfiguration.allowedHosts` when your account uses one.
    public static let platformHosts: Set<String> = ["wthaiq.com", "www.wthaiq.com"]
}
