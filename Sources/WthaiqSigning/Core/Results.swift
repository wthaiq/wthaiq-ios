import Foundation

/// Identifiers of the signature request and signer, when the page or the return URL provides them.
public struct SigningReference: Hashable, Sendable {
    /// The signature request (or session) id, `sr_…`.
    public let signatureRequestID: String?
    /// The signer id, `sgr_…`.
    public let signerID: String?

    public init(signatureRequestID: String? = nil, signerID: String? = nil) {
        self.signatureRequestID = signatureRequestID
        self.signerID = signerID
    }

    /// No identifiers available.
    public static let unknown = SigningReference()

    /// `true` when neither identifier is known.
    public var isEmpty: Bool {
        signatureRequestID == nil && signerID == nil
    }
}

/// Details of a signed or declined result.
public struct SigningOutcome: Hashable, Sendable {
    /// How the SDK learned the outcome.
    public enum Detection: String, Hashable, Sendable {
        /// The page navigated to one of your return URLs.
        case returnURL = "return_url"
        /// The page sent a signing event.
        case pageEvent = "page_event"
        /// The SDK read the outcome from the page content (best effort).
        case pageContent = "page_content"
    }

    /// Request and signer identifiers, when known.
    public let reference: SigningReference
    /// How the outcome was detected.
    public let detection: Detection
    /// The return URL the page navigated to, for `.returnURL`.
    public let returnURL: URL?
    /// `true` when the link had already been signed or declined before it was opened.
    public let wasAlreadyFinal: Bool
    /// A reason code sent by the page, for example `signer_declined`.
    public let reason: String?

    public init(
        reference: SigningReference = .unknown,
        detection: Detection,
        returnURL: URL? = nil,
        wasAlreadyFinal: Bool = false,
        reason: String? = nil
    ) {
        self.reference = reference
        self.detection = detection
        self.returnURL = returnURL
        self.wasAlreadyFinal = wasAlreadyFinal
        self.reason = reason
    }
}

/// How a signing session ended. Delivered exactly once.
///
/// This is a signal for your interface, not proof of signature: confirm the final state on your backend
/// with the `signature_request.completed` / `signer.signed` webhooks or `GET /signature_requests/{id}`.
public enum SigningResult: Hashable, Sendable {
    /// The signer signed (or had already signed this link).
    case signed(SigningOutcome)
    /// The signer declined (or had already declined this link).
    case declined(SigningOutcome)
    /// The signer closed the view before finishing, or the app canceled the session.
    case canceled
    /// The signing link or embedded session has expired. Ask your backend for a new one.
    case expired
    /// The session could not continue.
    case failed(WthaiqSigningError)

    /// `true` for `.signed`.
    public var isSigned: Bool {
        if case .signed = self {
            return true
        }
        return false
    }

    /// The outcome of `.signed` and `.declined`.
    public var outcome: SigningOutcome? {
        switch self {
        case .signed(let outcome), .declined(let outcome):
            return outcome
        case .canceled, .expired, .failed:
            return nil
        }
    }

    /// Parses a return URL your app received some other way (for example through a universal link after
    /// signing in Safari). Returns `nil` unless the URL carries `status=completed` or `status=declined`.
    public init?(returnURL url: URL) {
        let match = ReturnURLMatch(url: url)
        let reference = SigningReference(signatureRequestID: match.signatureRequestID, signerID: match.signerID)
        let outcome = SigningOutcome(reference: reference, detection: .returnURL, returnURL: url)
        switch match.status {
        case .completed:
            self = .signed(outcome)
        case .declined:
            self = .declined(outcome)
        case .unspecified, .other:
            return nil
        }
    }
}

/// States the signing page can show instead of the signing form.
public enum SigningPageState: String, Hashable, Sendable, CaseIterable {
    /// This signer already signed. Ends the session with `.signed` (`wasAlreadyFinal`).
    case alreadySigned = "already_signed"
    /// This signer already declined. Ends the session with `.declined` (`wasAlreadyFinal`).
    case alreadyDeclined = "already_declined"
    /// The link has expired. Ends the session with `.expired`.
    case expired
    /// The sender canceled the request. Ends the session with `.failed(.linkUnavailable(.canceled))`.
    case canceled
    /// No request matches the link. Ends the session with `.failed(.linkUnavailable(.notFound))`.
    case notFound = "not_found"
    /// The link has no signing token. Ends the session with `.failed(.linkUnavailable(.missingToken))`.
    case missingToken = "missing_token"
    /// Ordered signing: an earlier signer has not signed yet. The view stays open.
    case notYourTurn = "not_your_turn"
    /// The page asks for the access code sent separately by the sender. The view stays open.
    case accessCodeRequired = "access_code"
    /// In-person signing is paused because identity verification is unavailable. The view stays open.
    case identityUnavailable = "identity_unavailable"

    /// `true` when this state ends the session.
    public var isFinal: Bool {
        switch self {
        case .notYourTurn, .accessCodeRequired, .identityUnavailable:
            return false
        case .alreadySigned, .alreadyDeclined, .expired, .canceled, .notFound, .missingToken:
            return true
        }
    }
}

/// Errors reported in `SigningResult.failed` and `SigningEvent.loadFailed`.
public enum WthaiqSigningError: Error, Hashable, Sendable {
    /// The URL was refused before loading.
    case invalidURL(URLValidationError)
    /// A network error (`URLError` code and its message).
    case network(code: Int, message: String)
    /// The page did not finish loading within `WthaiqSigningConfiguration.timeout`.
    case timedOut
    /// The signing page answered with an HTTP error (429 or 5xx).
    case httpStatus(Int)
    /// The link cannot be signed (`.canceled`, `.notFound` or `.missingToken`).
    case linkUnavailable(SigningPageState)
    /// The page reported an error with this reason code.
    case pageError(String)
    /// The web content process stopped repeatedly.
    case webContentTerminated
    /// A return URL carried an unknown `status` value.
    case unexpectedReturnStatus(String)

    /// `true` when trying again may help.
    public var isRetryable: Bool {
        switch self {
        case .network, .timedOut, .httpStatus, .webContentTerminated:
            return true
        case .invalidURL, .linkUnavailable, .pageError, .unexpectedReturnStatus:
            return false
        }
    }

    /// `true` for network errors caused by a missing or lost connection.
    public var isOffline: Bool {
        guard case .network(let code, _) = self else { return false }
        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed
        ].contains(code)
    }
}

extension WthaiqSigningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let reason):
            return reason.errorDescription
        case let .network(code, message):
            return "Network error \(code): \(message)"
        case .timedOut:
            return "The signing page did not finish loading in time."
        case .httpStatus(let status):
            return "The signing page answered with HTTP \(status)."
        case .linkUnavailable(let state):
            return "The signing link cannot be used (\(state.rawValue))."
        case .pageError(let reason):
            return "The signing page reported an error (\(reason))."
        case .webContentTerminated:
            return "The web content process stopped unexpectedly."
        case .unexpectedReturnStatus(let status):
            return "The return URL carried an unknown status (\(status))."
        }
    }
}

/// Informational events reported while the session runs.
public enum SigningEvent: Hashable, Sendable {
    /// A page finished loading in the main frame.
    case pageLoaded(URL)
    /// The embedded signing page reported that the signer opened the document.
    case viewed(SigningReference)
    /// The page shows a state that does not end the session (see `SigningPageState.isFinal`).
    case pageStateChanged(SigningPageState)
    /// The identity verification step opened on a third-party host.
    case identityVerificationStarted(host: String)
    /// A link was handed to the system (Safari, Mail, Phone).
    case externalURLOpened(URL)
    /// A navigation was refused by the navigation policy.
    case navigationBlocked(URL)
    /// A page failed to load; the retry screen is shown.
    case loadFailed(WthaiqSigningError)
    /// A page message this version does not know, kept for forward compatibility.
    case pageMessage(name: String, fields: [String: String])
}
