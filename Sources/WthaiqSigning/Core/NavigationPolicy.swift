import Foundation

/// What started a navigation (mirrors `WKNavigationType` without importing WebKit).
enum NavigationTrigger: Hashable, Sendable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
}

/// A navigation the web view is about to perform.
struct NavigationRequest: Hashable, Sendable {
    var url: URL
    var isMainFrame: Bool = true
    var opensNewWindow: Bool = false
    var trigger: NavigationTrigger = .other
    /// Host of the frame that started the navigation, when WebKit provides it.
    var sourceHost: String?
}

enum NavigationBlockReason: Hashable, Sendable {
    case unsupportedScheme
    case insecureConnection
    case hostNotAllowed
    case finished
}

enum NavigationDecision: Hashable, Sendable {
    /// Load it in the signing view.
    case allow
    /// Load it and remember the host as part of the identity verification step.
    case allowExternalFlow(host: String)
    /// Do not load it.
    case cancel(NavigationBlockReason)
    /// Do not load it; hand it to the system (Safari, Mail, Phone).
    case openExternally(URL)
    /// Do not load it; the session ends with this return URL.
    case complete(ReturnURLMatch)
}

enum MediaCaptureKind: Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
}

/// Which privacy usage descriptions the host app declares. Without them iOS terminates the app when a page
/// asks for the camera or microphone, so the SDK denies those requests instead.
struct UsageDescriptions: Hashable, Sendable {
    var camera: Bool
    var microphone: Bool

    static func read(from bundle: Bundle = .main) -> UsageDescriptions {
        func declared(_ key: String) -> Bool {
            guard let text = bundle.object(forInfoDictionaryKey: key) as? String else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return UsageDescriptions(
            camera: declared("NSCameraUsageDescription"),
            microphone: declared("NSMicrophoneUsageDescription")
        )
    }
}

/// Decides what the signing view does with every navigation. Pure logic, no WebKit, fully unit tested.
///
/// Rules, in order:
/// 1. A URL matching one of `returnURLs` ends the session (never loaded).
/// 2. `about:` is allowed; `data:`/`blob:` only in subframes; `mailto:`/`tel:`/`sms:` open in the system
///    when the signer tapped them; every other non-web scheme is refused.
/// 3. New-window requests (`target="_blank"`, `window.open`) open in Safari.
/// 4. Plain `http` is refused (except local development hosts when enabled); a tapped `http` link opens in Safari.
/// 5. A platform page navigating to `…?session_id=sr_…&status=completed|declined` ends the session.
/// 6. Platform hosts are allowed. After the session has ended, any other main-frame navigation is refused.
/// 7. Identity verification hosts (listed, or admitted earlier in this session) are allowed.
/// 8. A tapped link to another host opens in Safari.
/// 9. A scripted navigation or redirect from a platform page (or an admitted host) to another https host is
///    admitted as the identity verification step under `.followPlatform`.
/// 10. Everything else is refused.
struct NavigationPolicy: Sendable {
    let configuration: WthaiqSigningConfiguration
    private(set) var admittedHosts: Set<String> = []
    private(set) var isFinished = false

    init(configuration: WthaiqSigningConfiguration) {
        self.configuration = configuration
    }

    mutating func markFinished() {
        isFinished = true
    }

    func isPlatformHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let normalized = HostMatcher.normalize(host)
        guard !normalized.isEmpty else { return false }
        if HostMatcher.matches(normalized, patterns: configuration.allowedHosts) {
            return true
        }
        return configuration.allowsInsecureLocalHosts && HostMatcher.isLocalDevelopmentHost(normalized)
    }

    /// Hosts whose pages may use the camera and microphone: platform hosts and identity verification hosts.
    func isTrustedContentHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let normalized = HostMatcher.normalize(host)
        return isPlatformHost(normalized)
            || admittedHosts.contains(normalized)
            || HostMatcher.matches(normalized, patterns: configuration.identityVerificationHosts)
    }

    func isSecure(scheme: String, host: String) -> Bool {
        let lower = scheme.lowercased()
        if lower == "https" {
            return true
        }
        return lower == "http" && configuration.allowsInsecureLocalHosts && HostMatcher.isLocalDevelopmentHost(host)
    }

    /// `true` for a frame (scheme and host of its security origin) on a platform host.
    func isPlatformFrame(scheme: String, host: String) -> Bool {
        isSecure(scheme: scheme, host: host) && isPlatformHost(host)
    }

    /// `true` for a `MessageEvent.origin` string such as `https://wthaiq.com`.
    func isPlatformOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let scheme = url.scheme, let host = url.host else { return false }
        return isPlatformFrame(scheme: scheme, host: host)
    }

    func allowsMediaCapture(_ kind: MediaCaptureKind, scheme: String, host: String, usage: UsageDescriptions) -> Bool {
        guard isSecure(scheme: scheme, host: host), isTrustedContentHost(host) else { return false }
        switch kind {
        case .camera:
            return usage.camera
        case .microphone:
            return usage.microphone
        case .cameraAndMicrophone:
            return usage.camera && usage.microphone
        }
    }

    mutating func decide(_ request: NavigationRequest) -> NavigationDecision {
        let url = request.url
        let scheme = url.scheme?.lowercased() ?? ""

        if configuration.returnURLs.contains(where: { $0.matches(url) }) {
            return isFinished ? .cancel(.finished) : .complete(ReturnURLMatch(url: url))
        }

        switch scheme {
        case "about":
            return .allow
        case "data", "blob":
            return (request.isMainFrame || request.opensNewWindow) ? .cancel(.unsupportedScheme) : .allow
        case "mailto", "tel", "sms":
            let tapped = request.trigger == .linkActivated || request.opensNewWindow
            return tapped ? .openExternally(url) : .cancel(.unsupportedScheme)
        case "http", "https":
            break
        default:
            return .cancel(.unsupportedScheme)
        }

        let host = HostMatcher.normalize(url.host ?? "")
        guard !host.isEmpty else { return .cancel(.hostNotAllowed) }

        if request.opensNewWindow {
            return .openExternally(url)
        }

        guard isSecure(scheme: scheme, host: host) else {
            return request.trigger == .linkActivated ? .openExternally(url) : .cancel(.insecureConnection)
        }

        let fromPlatform = isPlatformHost(request.sourceHost)
        if configuration.detectsPlatformReturnNavigation, fromPlatform, !isPlatformHost(host) {
            let match = ReturnURLMatch(url: url)
            if match.isPlatformReturnTarget {
                return isFinished ? .cancel(.finished) : .complete(match)
            }
        }

        if isPlatformHost(host) {
            return .allow
        }
        if isFinished && request.isMainFrame {
            return .cancel(.finished)
        }
        if admittedHosts.contains(host) || HostMatcher.matches(host, patterns: configuration.identityVerificationHosts) {
            return .allow
        }
        if request.trigger == .linkActivated {
            return .openExternally(url)
        }
        if request.trigger == .other, configuration.identityVerification == .followPlatform, !isFinished {
            let sourceAdmitted = request.sourceHost.map { admittedHosts.contains(HostMatcher.normalize($0)) } ?? false
            if fromPlatform || sourceAdmitted {
                admittedHosts.insert(host)
                return .allowExternalFlow(host: host)
            }
        }
        return .cancel(.hostNotAllowed)
    }
}
