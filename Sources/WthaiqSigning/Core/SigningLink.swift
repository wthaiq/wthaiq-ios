import Foundation

/// Why a URL was refused before anything was loaded.
public enum URLValidationError: Error, Hashable, Sendable {
    /// No URL was provided.
    case missingURL
    /// The scheme is not `https` (plain `http` is accepted only for local development hosts when
    /// `allowsInsecureLocalHosts` is enabled).
    case unsupportedScheme(String)
    /// The URL has no host.
    case missingHost
    /// The host is not in `WthaiqSigningConfiguration.allowedHosts`.
    case hostNotAllowed(String)
    /// The URL contains a user name or password.
    case containsCredentials
    /// A signing page URL without its signing token.
    case missingToken
}

extension URLValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return "No signing URL was provided."
        case .unsupportedScheme(let scheme):
            return "Signing URLs must use https (got \"\(scheme)\")."
        case .missingHost:
            return "The signing URL has no host."
        case .hostNotAllowed(let host):
            return "The host \"\(host)\" is not an allowed signing host. Add your custom signing domain to allowedHosts."
        case .containsCredentials:
            return "Signing URLs must not contain a user name or password."
        case .missingToken:
            return "The signing URL has no signing token."
        }
    }
}

/// A signing URL that passed validation.
///
/// Use `SigningLink.validate(_:configuration:)` on the URL your backend returns before showing it, or let
/// `WthaiqSigningViewController` do it for you.
public struct SigningLink: Hashable, Sendable {
    /// The kind of signing URL.
    public enum Kind: String, Hashable, Sendable {
        /// `https://<host>/sign.php?token=…` (`signing_url` / `sign_url` from the API).
        case signingPage = "signing_page"
        /// `https://wthaiq.com/embed/sign/<token>` (`POST /signers/{id}/signing_session`).
        case embeddedSession = "embedded_session"
        /// Another page on an allowed host.
        case other
    }

    /// The validated URL, unchanged.
    public let url: URL
    /// The kind of signing URL.
    public let kind: Kind
    /// The normalized host.
    public let host: String

    /// Validates `url` against `configuration` and returns the result without throwing.
    public static func check(
        _ url: URL?,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration()
    ) -> Result<SigningLink, URLValidationError> {
        guard let url else { return .failure(.missingURL) }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = HostMatcher.normalize(url.host ?? "")
        let isLocal = configuration.allowsInsecureLocalHosts && HostMatcher.isLocalDevelopmentHost(host)

        guard scheme == "https" || (scheme == "http" && isLocal) else {
            return .failure(.unsupportedScheme(scheme))
        }
        guard !host.isEmpty else { return .failure(.missingHost) }
        guard url.user == nil, url.password == nil else { return .failure(.containsCredentials) }
        guard HostMatcher.matches(host, patterns: configuration.allowedHosts) || isLocal else {
            return .failure(.hostNotAllowed(host))
        }

        switch classify(url) {
        case .success(let kind):
            return .success(SigningLink(url: url, kind: kind, host: host))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Validates `url` against `configuration`.
    public static func validate(
        _ url: URL,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration()
    ) throws -> SigningLink {
        try check(url, configuration: configuration).get()
    }

    /// Returns `true` when `url` is a valid signing URL for `configuration`.
    public static func isValid(
        _ url: URL,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration()
    ) -> Bool {
        if case .success = check(url, configuration: configuration) {
            return true
        }
        return false
    }

    /// The URL to load for `language`: adds `lang=ar` or `lang=en` unless the URL already has a `lang`
    /// parameter. `.automatic` leaves the URL unchanged.
    public func url(for language: WthaiqSigningConfiguration.Language) -> URL {
        guard language != .automatic,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.percentEncodedQueryItems ?? []
        guard !items.contains(where: { $0.name == "lang" }) else { return url }
        items.append(URLQueryItem(name: "lang", value: language.rawValue))
        components.percentEncodedQueryItems = items
        return components.url ?? url
    }

    private static func classify(_ url: URL) -> Result<Kind, URLValidationError> {
        var path = url.path
        if path.lowercased().hasPrefix("/en/") {
            path = String(path.dropFirst(3))
        }
        let lower = path.lowercased()
        if lower == "/sign.php" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let token = items.first(where: { $0.name == "token" })?.value ?? ""
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.missingToken)
            }
            return .success(.signingPage)
        }
        let embedPrefix = "/embed/sign"
        if lower == embedPrefix || lower.hasPrefix(embedPrefix + "/") {
            var token = String(path.dropFirst(embedPrefix.count))
            while token.hasPrefix("/") {
                token.removeFirst()
            }
            while token.hasSuffix("/") {
                token.removeLast()
            }
            let isToken = !token.isEmpty && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            return isToken ? .success(.embeddedSession) : .failure(.missingToken)
        }
        return .success(.other)
    }
}
