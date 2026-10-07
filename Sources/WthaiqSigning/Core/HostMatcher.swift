import Foundation

/// Host comparison rules shared by URL validation, the navigation policy and the page message gate.
enum HostMatcher {
    /// Lowercases, trims whitespace, removes IPv6 brackets and trailing dots.
    static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.count >= 2, value.hasPrefix("["), value.hasSuffix("]") {
            value = String(value.dropFirst().dropLast())
        }
        while value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }

    /// Returns `true` when `host` equals one of `patterns`, or is a subdomain of a `*.example.com` pattern.
    /// A wildcard pattern never matches its apex domain.
    static func matches(_ host: String, patterns: Set<String>) -> Bool {
        let candidate = normalize(host)
        guard !candidate.isEmpty else { return false }
        for raw in patterns {
            let pattern = normalize(raw)
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst())
                if suffix.count > 1, candidate.count > suffix.count, candidate.hasSuffix(suffix) {
                    return true
                }
            } else if !pattern.isEmpty, pattern == candidate {
                return true
            }
        }
        return false
    }

    /// Hosts that only exist on a developer machine. Plain `http` is accepted for them when
    /// `WthaiqSigningConfiguration.allowsInsecureLocalHosts` is enabled.
    static func isLocalDevelopmentHost(_ host: String) -> Bool {
        let value = normalize(host)
        if value == "localhost" || value == "127.0.0.1" || value == "::1" {
            return true
        }
        return value.hasSuffix(".localhost") || value.hasSuffix(".test")
    }
}
