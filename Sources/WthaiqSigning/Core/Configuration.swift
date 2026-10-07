import Foundation

/// Options for one signing session. Every property has a safe default, so `WthaiqSigningConfiguration()`
/// works for links on `wthaiq.com`.
public struct WthaiqSigningConfiguration: Hashable, Sendable {

    /// The language of the SDK's own interface (title, buttons, error screens) and, when set explicitly,
    /// of the signing page.
    public enum Language: String, Hashable, Sendable, CaseIterable {
        /// Follow the app's current localization for the SDK's interface. The signing page keeps the
        /// language chosen when the request was created (`language` on `POST /sessions`).
        case automatic
        /// Arabic, right to left. Adds `lang=ar` to the signing URL.
        case arabic = "ar"
        /// English, left to right. Adds `lang=en` to the signing URL.
        case english = "en"
    }

    /// Which third-party hosts may load inside the signing view during identity verification.
    public enum IdentityVerificationPolicy: Hashable, Sendable {
        /// Allow a host that a platform page navigates to by script or redirect (this is how the signing page
        /// opens the identity verification step), plus `identityVerificationHosts`. Links the signer taps
        /// to other hosts still open in Safari.
        case followPlatform
        /// Allow only `identityVerificationHosts`. Identity verification fails if its host is not listed.
        case listedHostsOnly
    }

    /// What happens after the signer signs or declines.
    public enum DismissalBehavior: Hashable, Sendable {
        /// Ask the container to dismiss the view after the given number of seconds, so the signer sees the
        /// page's confirmation first. Other results (expired, failed) never dismiss automatically.
        case automatic(after: TimeInterval)
        /// Keep the view on screen until the signer taps Close.
        case manual
    }

    /// Light or dark appearance for the SDK's interface.
    public enum InterfaceStyle: String, Hashable, Sendable, CaseIterable {
        case system
        case light
        case dark
    }

    /// Visual options.
    public struct Appearance: Hashable, Sendable {
        /// Tint for buttons and the progress bar. Defaults to the Wthaiq brand blue.
        public var tintColor: SigningColor
        /// Light, dark or the system setting. The signing page itself is always light.
        public var interfaceStyle: InterfaceStyle
        /// Title shown above the page. `nil` uses "Sign document" in the session language.
        public var title: String?
        /// Show the SDK's title bar. When the view controller is inside a `UINavigationController`, the
        /// navigation bar is used instead.
        public var showsHeader: Bool
        /// Show a thin progress bar while pages load.
        public var showsProgressBar: Bool
        /// Ask for confirmation when the signer closes the view before finishing.
        public var confirmsBeforeClosing: Bool

        public init(
            tintColor: SigningColor = .brand,
            interfaceStyle: InterfaceStyle = .system,
            title: String? = nil,
            showsHeader: Bool = true,
            showsProgressBar: Bool = true,
            confirmsBeforeClosing: Bool = true
        ) {
            self.tintColor = tintColor
            self.interfaceStyle = interfaceStyle
            self.title = title
            self.showsHeader = showsHeader
            self.showsProgressBar = showsProgressBar
            self.confirmsBeforeClosing = confirmsBeforeClosing
        }
    }

    /// The hosts that serve Wthaiq signing pages.
    public static let platformHosts: Set<String> = WthaiqSigningSDK.platformHosts
    /// Default page-load timeout in seconds.
    public static let defaultTimeout: TimeInterval = 30
    /// Accepted range for `timeout`; values outside it are clamped.
    public static let timeoutRange: ClosedRange<TimeInterval> = 5...120
    /// Default delay before an automatic dismissal.
    public static let defaultDismissalDelay: TimeInterval = 1.5

    /// Language of the SDK's interface and, when explicit, of the signing page.
    public var language: Language
    /// Hosts allowed to serve the signing page (exact hosts or `*.example.com`). Add your custom signing
    /// domain here. Page events are trusted only from these hosts.
    public var allowedHosts: Set<String>
    /// Your return URLs (`return_url`, `success_url`, `cancel_url`). Navigation to a matching URL ends the
    /// session; it is never loaded inside the view.
    public var returnURLs: [ReturnURLPattern]
    /// Show a Close button.
    public var showsCloseButton: Bool
    /// Visual options.
    public var appearance: Appearance
    /// Seconds to wait for a page to load before showing the retry screen (clamped to `timeoutRange`).
    public var timeout: TimeInterval
    /// What happens after the signer signs or declines.
    public var dismissal: DismissalBehavior
    /// Which third-party hosts may load during identity verification.
    public var identityVerification: IdentityVerificationPolicy
    /// Hosts always allowed for identity verification (exact hosts or `*.example.com`).
    public var identityVerificationHosts: Set<String>
    /// Recognise the platform's own return navigation (`?session_id=sr_…&signer_id=…&status=…`) even when
    /// its URL is not listed in `returnURLs`.
    public var detectsPlatformReturnNavigation: Bool
    /// Keep cookies and storage in memory only, so nothing from the signing session stays on the device.
    public var usesEphemeralWebsiteData: Bool
    /// Development only: accept `http` and any local host (`localhost`, `127.0.0.1`, `*.localhost`, `*.test`).
    public var allowsInsecureLocalHosts: Bool
    /// Development only: allow Safari Web Inspector to attach (iOS 16.4 and later).
    public var isInspectable: Bool

    public init(
        language: Language = .automatic,
        allowedHosts: Set<String> = WthaiqSigningConfiguration.platformHosts,
        returnURLs: [ReturnURLPattern] = [],
        showsCloseButton: Bool = true,
        appearance: Appearance = Appearance(),
        timeout: TimeInterval = WthaiqSigningConfiguration.defaultTimeout,
        dismissal: DismissalBehavior = .automatic(after: WthaiqSigningConfiguration.defaultDismissalDelay),
        identityVerification: IdentityVerificationPolicy = .followPlatform,
        identityVerificationHosts: Set<String> = [],
        detectsPlatformReturnNavigation: Bool = true,
        usesEphemeralWebsiteData: Bool = true,
        allowsInsecureLocalHosts: Bool = false,
        isInspectable: Bool = false
    ) {
        self.language = language
        self.allowedHosts = allowedHosts
        self.returnURLs = returnURLs
        self.showsCloseButton = showsCloseButton
        self.appearance = appearance
        self.timeout = timeout
        self.dismissal = dismissal
        self.identityVerification = identityVerification
        self.identityVerificationHosts = identityVerificationHosts
        self.detectsPlatformReturnNavigation = detectsPlatformReturnNavigation
        self.usesEphemeralWebsiteData = usesEphemeralWebsiteData
        self.allowsInsecureLocalHosts = allowsInsecureLocalHosts
        self.isInspectable = isInspectable
    }

    /// Adds a return URL (scheme, host and path prefix are matched; the query is ignored).
    /// Returns `false` when the URL cannot be used as a pattern (an `http(s)` URL without a host).
    @discardableResult
    public mutating func addReturnURL(_ url: URL) -> Bool {
        guard let pattern = ReturnURLPattern(url: url) else { return false }
        if !returnURLs.contains(pattern) {
            returnURLs.append(pattern)
        }
        return true
    }

    /// Allows another host to serve the signing page, for example your custom signing domain.
    public mutating func addAllowedHost(_ host: String) {
        let normalized = HostMatcher.normalize(host)
        guard !normalized.isEmpty else { return }
        allowedHosts.insert(normalized)
    }

    /// `timeout` clamped to `timeoutRange`; a non-finite value falls back to the default.
    var effectiveTimeout: TimeInterval {
        guard timeout.isFinite else { return Self.defaultTimeout }
        return min(max(timeout, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
    }

    /// Seconds before an automatic dismissal, or `nil` for `.manual`. Clamped to 0...30.
    var dismissalDelay: TimeInterval? {
        switch dismissal {
        case .manual:
            return nil
        case .automatic(let seconds):
            guard seconds.isFinite else { return Self.defaultDismissalDelay }
            return min(max(seconds, 0), 30)
        }
    }
}

/// The language actually used once `.automatic` has been resolved.
enum ResolvedLanguage: String, Hashable, Sendable {
    case arabic = "ar"
    case english = "en"

    var isRightToLeft: Bool { self == .arabic }

    static func resolve(_ language: WthaiqSigningConfiguration.Language, preferredLanguages: [String]) -> ResolvedLanguage {
        switch language {
        case .arabic:
            return .arabic
        case .english:
            return .english
        case .automatic:
            let first = preferredLanguages.first?.lowercased() ?? ""
            return first.hasPrefix("ar") ? .arabic : .english
        }
    }

    /// The app's own localization order, so the SDK matches the language the app is shown in.
    static func appPreferredLanguages(bundle: Bundle = .main) -> [String] {
        bundle.preferredLocalizations
    }
}
