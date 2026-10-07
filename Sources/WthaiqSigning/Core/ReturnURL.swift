import Foundation

/// Describes one of your return URLs. Navigation to a matching URL ends the signing session instead of
/// loading your page inside the signing view.
///
/// Scheme and host are compared case-insensitively; the path matches when it equals `pathPrefix` or continues
/// it after a `/`. The query, fragment and port are ignored. An `http(s)` pattern always needs a host.
public struct ReturnURLPattern: Hashable, Sendable, CustomStringConvertible {
    /// Lowercased scheme, for example `https` or your app's custom scheme.
    public let scheme: String
    /// Normalized host, or `nil` to accept any host (custom schemes only).
    public let host: String?
    /// Normalized path prefix (`/` accepts any path).
    public let pathPrefix: String

    public init(scheme: String, host: String? = nil, pathPrefix: String = "/") {
        self.scheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHost = host.map(HostMatcher.normalize) ?? ""
        self.host = normalizedHost.isEmpty ? nil : normalizedHost
        self.pathPrefix = Self.normalizePath(pathPrefix)
    }

    /// Builds a pattern from a full URL such as `https://example.com/signing/done`. Returns `nil` for an
    /// `http(s)` URL without a host or a URL without a scheme.
    public init?(url: URL) {
        guard let scheme = url.scheme, !scheme.isEmpty else { return nil }
        let host = url.host ?? ""
        if Self.isWebScheme(scheme.lowercased()) && host.isEmpty {
            return nil
        }
        self.init(scheme: scheme, host: host.isEmpty ? nil : host, pathPrefix: url.path)
    }

    /// Builds a pattern from a URL string.
    public init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }

    /// Returns `true` when `url` is covered by this pattern.
    public func matches(_ url: URL) -> Bool {
        guard let candidateScheme = url.scheme?.lowercased(), candidateScheme == scheme else { return false }
        if let host {
            guard HostMatcher.normalize(url.host ?? "") == host else { return false }
        } else if Self.isWebScheme(scheme) {
            return false
        }
        if pathPrefix == "/" {
            return true
        }
        let path = Self.normalizePath(url.path)
        return path == pathPrefix || path.hasPrefix(pathPrefix + "/")
    }

    public var description: String {
        "\(scheme)://\(host ?? "*")\(pathPrefix)"
    }

    static func isWebScheme(_ scheme: String) -> Bool {
        scheme == "https" || scheme == "http"
    }

    static func normalizePath(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.hasPrefix("/") {
            value = "/" + value
        }
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

/// The parts of a return URL that the signing page adds:
/// `?session_id=sr_…&signer_id=sgr_…&status=completed|declined`.
public struct ReturnURLMatch: Hashable, Sendable {
    /// The `status` query parameter.
    public enum Status: Hashable, Sendable {
        /// `status=completed`: the signer signed.
        case completed
        /// `status=declined`: the signer declined.
        case declined
        /// No `status` parameter. The embedded signing page navigates to the plain `return_url` only after
        /// the signer has signed.
        case unspecified
        /// Any other value.
        case other(String)
    }

    /// The full URL the page navigated to.
    public let url: URL
    /// The parsed `status`.
    public let status: Status
    /// `session_id` (the signature request id, `sr_…`).
    public let signatureRequestID: String?
    /// `signer_id` (`sgr_…`).
    public let signerID: String?

    public init(url: URL) {
        self.url = url
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }
            return trimmed
        }
        switch value("status")?.lowercased() {
        case nil:
            status = .unspecified
        case "completed"?:
            status = .completed
        case "declined"?:
            status = .declined
        case let other?:
            status = .other(other)
        }
        signatureRequestID = value("session_id")
        signerID = value("signer_id")
    }

    /// `true` when the query has the exact shape the signing page appends to a return URL.
    var isPlatformReturnTarget: Bool {
        guard let identifier = signatureRequestID, identifier.hasPrefix("sr_") else { return false }
        switch status {
        case .completed, .declined:
            return true
        case .unspecified, .other:
            return false
        }
    }
}
