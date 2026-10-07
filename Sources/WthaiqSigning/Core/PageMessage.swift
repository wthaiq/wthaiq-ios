import Foundation

/// A signal decoded from the page bridge.
enum PageSignal: Hashable, Sendable {
    case viewed(SigningReference)
    case signed(SigningReference, SigningOutcome.Detection)
    case declined(SigningReference, reason: String?, SigningOutcome.Detection)
    case failed(reason: String)
    case state(SigningPageState, SigningReference, SigningOutcome.Detection)
    case other(name: String, fields: [String: String])
}

/// Decodes the bodies posted by `BridgeScript` to the `wthaiqSigning` message handler.
///
/// Two kinds are posted:
/// * `{kind: "message", origin, data}` — a `window` message from the signing page
///   (`data.source` is `wthaiq` or `wthaiq-inner`; see API-SPEC §8.13).
/// * `{kind: "dom", event, state?}` — an outcome read from the signing page content.
enum PageMessageDecoder {
    static let maxFieldLength = 200

    static func decode(_ body: Any, isTrustedOrigin: (String) -> Bool) -> PageSignal? {
        guard let dictionary = body as? [String: Any], let kind = dictionary["kind"] as? String else { return nil }
        switch kind {
        case "message":
            guard let origin = dictionary["origin"] as? String, isTrustedOrigin(origin),
                  let data = dictionary["data"] as? [String: Any] else { return nil }
            return decodePageMessage(stringFields(data))
        case "dom":
            guard let event = dictionary["event"] as? String else { return nil }
            return decodeContent(event: event, state: dictionary["state"] as? String)
        default:
            return nil
        }
    }

    static func stringFields(_ data: [String: Any]) -> [String: String] {
        var fields: [String: String] = [:]
        for (key, value) in data {
            if let text = value as? String {
                fields[key] = text
            } else if let number = value as? NSNumber {
                fields[key] = number.stringValue
            }
        }
        return fields
    }

    static func decodePageMessage(_ fields: [String: String]) -> PageSignal? {
        guard let source = fields["source"], source == "wthaiq" || source == "wthaiq-inner" else { return nil }
        var name = clean(fields["event"]) ?? ""
        if name.isEmpty, let type = clean(fields["type"]), type.hasPrefix("wthaiq:") {
            name = String(type.dropFirst("wthaiq:".count))
        }
        name = name.lowercased()
        guard !name.isEmpty, name.count <= 64 else { return nil }

        let reference = SigningReference(
            signatureRequestID: clean(fields["signature_request"]),
            signerID: clean(fields["signer"])
        )
        let reason = clean(fields["reason"])

        switch name {
        case "viewed":
            return .viewed(reference)
        case "signed", "completed":
            return .signed(reference, .pageEvent)
        case "declined":
            return .declined(reference, reason: reason, .pageEvent)
        case "error":
            return .failed(reason: reason ?? "unknown")
        case "state":
            guard let raw = clean(fields["state"]), let state = SigningPageState(rawValue: raw.lowercased()) else {
                return nil
            }
            return .state(state, reference, .pageEvent)
        default:
            var extra = fields
            extra.removeValue(forKey: "source")
            return .other(name: name, fields: extra)
        }
    }

    static func decodeContent(event: String, state: String?) -> PageSignal? {
        switch event {
        case "signed":
            return .signed(.unknown, .pageContent)
        case "declined":
            return .declined(.unknown, reason: nil, .pageContent)
        case "state":
            guard let raw = clean(state), let value = SigningPageState(rawValue: raw) else { return nil }
            return .state(value, .unknown, .pageContent)
        default:
            return nil
        }
    }

    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= maxFieldLength else { return nil }
        return trimmed
    }
}

/// The session state machine: turns signals into events and the single final result.
struct SigningFlow: Hashable, Sendable {
    enum Effect: Hashable, Sendable {
        case ignored
        case event(SigningEvent)
        case finish(SigningResult)
    }

    private(set) var result: SigningResult?
    private(set) var pageState: SigningPageState?

    var isFinished: Bool { result != nil }

    mutating func apply(_ signal: PageSignal) -> Effect {
        guard result == nil else { return .ignored }
        switch signal {
        case .viewed(let reference):
            return .event(.viewed(reference))
        case let .signed(reference, detection):
            return finish(.signed(SigningOutcome(reference: reference, detection: detection)))
        case let .declined(reference, reason, detection):
            return finish(.declined(SigningOutcome(reference: reference, detection: detection, reason: reason)))
        case .failed(let reason):
            return finish(reason == "session_expired" ? .expired : .failed(.pageError(reason)))
        case let .state(state, reference, detection):
            return apply(state: state, reference: reference, detection: detection)
        case let .other(name, fields):
            return .event(.pageMessage(name: name, fields: fields))
        }
    }

    mutating func apply(returnMatch match: ReturnURLMatch) -> Effect {
        guard result == nil else { return .ignored }
        let reference = SigningReference(signatureRequestID: match.signatureRequestID, signerID: match.signerID)
        let outcome = SigningOutcome(reference: reference, detection: .returnURL, returnURL: match.url)
        switch match.status {
        case .completed, .unspecified:
            return finish(.signed(outcome))
        case .declined:
            return finish(.declined(outcome))
        case .other(let value):
            return finish(.failed(.unexpectedReturnStatus(value)))
        }
    }

    /// The signer or the app ended the session. A visible load error is reported instead of `.canceled`.
    mutating func cancel(showingError error: WthaiqSigningError?) -> Effect {
        guard result == nil else { return .ignored }
        if let error {
            return finish(.failed(error))
        }
        return finish(.canceled)
    }

    mutating func fail(_ error: WthaiqSigningError) -> Effect {
        guard result == nil else { return .ignored }
        return finish(.failed(error))
    }

    private mutating func apply(
        state: SigningPageState,
        reference: SigningReference,
        detection: SigningOutcome.Detection
    ) -> Effect {
        switch state {
        case .alreadySigned:
            return finish(.signed(SigningOutcome(reference: reference, detection: detection, wasAlreadyFinal: true)))
        case .alreadyDeclined:
            return finish(.declined(SigningOutcome(reference: reference, detection: detection, wasAlreadyFinal: true)))
        case .expired:
            return finish(.expired)
        case .canceled, .notFound, .missingToken:
            return finish(.failed(.linkUnavailable(state)))
        case .notYourTurn, .accessCodeRequired, .identityUnavailable:
            guard pageState != state else { return .ignored }
            pageState = state
            return .event(.pageStateChanged(state))
        }
    }

    private mutating func finish(_ value: SigningResult) -> Effect {
        result = value
        return .finish(value)
    }
}
