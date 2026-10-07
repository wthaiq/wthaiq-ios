import XCTest
@testable import WthaiqSigning

final class PageMessageTests: XCTestCase {
    private let trusted: (String) -> Bool = { $0 == "https://wthaiq.com" }

    private func message(_ data: [String: Any], origin: String = "https://wthaiq.com") -> [String: Any] {
        ["kind": "message", "origin": origin, "data": data]
    }

    func testEmbeddedSignedEvent() {
        let body = message([
            "source": "wthaiq", "event": "signed", "type": "wthaiq:signed",
            "signature_request": "sr_1", "signer": "sgr_2"
        ])
        let reference = SigningReference(signatureRequestID: "sr_1", signerID: "sgr_2")
        XCTAssertEqual(PageMessageDecoder.decode(body, isTrustedOrigin: trusted), .signed(reference, .pageEvent))
    }

    func testEmbeddedDeclinedEventKeepsReason() {
        let body = message(["source": "wthaiq", "event": "declined", "signer": "sgr_2", "reason": "signer_declined"])
        XCTAssertEqual(
            PageMessageDecoder.decode(body, isTrustedOrigin: trusted),
            .declined(SigningReference(signerID: "sgr_2"), reason: "signer_declined", .pageEvent)
        )
    }

    func testEmbeddedErrorAndViewed() {
        XCTAssertEqual(
            PageMessageDecoder.decode(message(["source": "wthaiq", "event": "error", "reason": "session_expired"]),
                                      isTrustedOrigin: trusted),
            .failed(reason: "session_expired")
        )
        XCTAssertEqual(
            PageMessageDecoder.decode(message(["source": "wthaiq", "event": "error"]), isTrustedOrigin: trusted),
            .failed(reason: "unknown")
        )
        XCTAssertEqual(
            PageMessageDecoder.decode(message(["source": "wthaiq", "event": "viewed", "signature_request": "sr_1"]),
                                      isTrustedOrigin: trusted),
            .viewed(SigningReference(signatureRequestID: "sr_1"))
        )
    }

    func testEventNameFallsBackToType() {
        let body = message(["source": "wthaiq", "type": "wthaiq:Signed"])
        XCTAssertEqual(PageMessageDecoder.decode(body, isTrustedOrigin: trusted), .signed(.unknown, .pageEvent))
    }

    func testInnerStateMessage() {
        let body = message(["source": "wthaiq-inner", "event": "state", "state": "not_your_turn"])
        XCTAssertEqual(PageMessageDecoder.decode(body, isTrustedOrigin: trusted), .state(.notYourTurn, .unknown, .pageEvent))
        let unknown = message(["source": "wthaiq-inner", "event": "state", "state": "new_state"])
        XCTAssertNil(PageMessageDecoder.decode(unknown, isTrustedOrigin: trusted))
    }

    func testUnknownEventIsForwarded() {
        let body = message(["source": "wthaiq", "event": "otp_verified", "signer": "sgr_2", "attempts": NSNumber(value: 2)])
        XCTAssertEqual(
            PageMessageDecoder.decode(body, isTrustedOrigin: trusted),
            .other(name: "otp_verified", fields: ["event": "otp_verified", "signer": "sgr_2", "attempts": "2"])
        )
    }

    func testUntrustedOriginOrSourceIsIgnored() {
        let signed: [String: Any] = ["source": "wthaiq", "event": "signed"]
        XCTAssertNil(PageMessageDecoder.decode(message(signed, origin: "https://evil.example"), isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(message(["source": "other", "event": "signed"]), isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(message(["event": "signed"]), isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(message(["source": "wthaiq"]), isTrustedOrigin: trusted))
    }

    func testMalformedBodiesAreIgnored() {
        XCTAssertNil(PageMessageDecoder.decode("signed", isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(["kind": "message"], isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(["kind": "other", "event": "signed"], isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(["origin": "https://wthaiq.com"], isTrustedOrigin: trusted))
    }

    func testOverlongIdentifiersAreDropped() {
        let long = String(repeating: "x", count: 300)
        let body = message(["source": "wthaiq", "event": "signed", "signature_request": long])
        XCTAssertEqual(PageMessageDecoder.decode(body, isTrustedOrigin: trusted), .signed(.unknown, .pageEvent))
    }

    func testPageContentSignals() {
        XCTAssertEqual(PageMessageDecoder.decode(["kind": "dom", "event": "signed"], isTrustedOrigin: trusted),
                       .signed(.unknown, .pageContent))
        XCTAssertEqual(PageMessageDecoder.decode(["kind": "dom", "event": "declined"], isTrustedOrigin: trusted),
                       .declined(.unknown, reason: nil, .pageContent))
        XCTAssertEqual(PageMessageDecoder.decode(["kind": "dom", "event": "state", "state": "expired"], isTrustedOrigin: trusted),
                       .state(.expired, .unknown, .pageContent))
        XCTAssertNil(PageMessageDecoder.decode(["kind": "dom", "event": "state", "state": "bogus"], isTrustedOrigin: trusted))
        XCTAssertNil(PageMessageDecoder.decode(["kind": "dom", "event": "other"], isTrustedOrigin: trusted))
    }

    func testEveryPageStateNameDecodes() {
        for state in SigningPageState.allCases {
            XCTAssertEqual(
                PageMessageDecoder.decode(["kind": "dom", "event": "state", "state": state.rawValue], isTrustedOrigin: trusted),
                .state(state, .unknown, .pageContent)
            )
        }
    }
}

final class SigningFlowTests: XCTestCase {
    func testSignedFinishesOnceAndIgnoresLaterSignals() {
        var flow = SigningFlow()
        let reference = SigningReference(signatureRequestID: "sr_1", signerID: "sgr_1")
        let expected = SigningResult.signed(SigningOutcome(reference: reference, detection: .pageEvent))
        XCTAssertEqual(flow.apply(.signed(reference, .pageEvent)), .finish(expected))
        XCTAssertEqual(flow.apply(.declined(.unknown, reason: nil, .pageContent)), .ignored)
        XCTAssertEqual(flow.cancel(showingError: nil), .ignored)
        XCTAssertEqual(flow.result, expected)
    }

    func testContentOutcomeUsesIdentifiersFromEarlierEvents() {
        var flow = SigningFlow()
        _ = flow.apply(.viewed(SigningReference(signatureRequestID: "sr_7")))
        _ = flow.apply(.viewed(SigningReference(signerID: "sgr_7")))
        let expected = SigningReference(signatureRequestID: "sr_7", signerID: "sgr_7")
        XCTAssertEqual(flow.knownReference, expected)
        XCTAssertEqual(flow.apply(.signed(.unknown, .pageContent)),
                       .finish(.signed(SigningOutcome(reference: expected, detection: .pageContent))))
    }

    func testDeclinedKeepsReason() {
        var flow = SigningFlow()
        let effect = flow.apply(.declined(.unknown, reason: "signer_declined", .pageEvent))
        XCTAssertEqual(effect, .finish(.declined(SigningOutcome(detection: .pageEvent, reason: "signer_declined"))))
    }

    func testViewedAndUnknownMessagesAreEvents() {
        var flow = SigningFlow()
        XCTAssertEqual(flow.apply(.viewed(.unknown)), .event(.viewed(.unknown)))
        XCTAssertEqual(flow.apply(.other(name: "x", fields: [:])), .event(.pageMessage(name: "x", fields: [:])))
        XCTAssertFalse(flow.isFinished)
    }

    func testErrorReasons() {
        var expired = SigningFlow()
        XCTAssertEqual(expired.apply(.failed(reason: "session_expired")), .finish(.expired))
        var other = SigningFlow()
        XCTAssertEqual(other.apply(.failed(reason: "boom")), .finish(.failed(.pageError("boom"))))
    }

    func testFinalPageStates() {
        let cases: [(SigningPageState, SigningResult)] = [
            (.alreadySigned, .signed(SigningOutcome(detection: .pageContent, wasAlreadyFinal: true))),
            (.alreadyDeclined, .declined(SigningOutcome(detection: .pageContent, wasAlreadyFinal: true))),
            (.expired, .expired),
            (.canceled, .failed(.linkUnavailable(.canceled))),
            (.notFound, .failed(.linkUnavailable(.notFound))),
            (.missingToken, .failed(.linkUnavailable(.missingToken)))
        ]
        for (state, expected) in cases {
            var flow = SigningFlow()
            XCTAssertTrue(state.isFinal)
            XCTAssertEqual(flow.apply(.state(state, .unknown, .pageContent)), .finish(expected), state.rawValue)
        }
    }

    func testNonFinalPageStatesAreReportedOncePerChange() {
        var flow = SigningFlow()
        XCTAssertFalse(SigningPageState.notYourTurn.isFinal)
        XCTAssertEqual(flow.apply(.state(.notYourTurn, .unknown, .pageContent)), .event(.pageStateChanged(.notYourTurn)))
        XCTAssertEqual(flow.apply(.state(.notYourTurn, .unknown, .pageContent)), .ignored)
        XCTAssertEqual(flow.apply(.state(.accessCodeRequired, .unknown, .pageContent)),
                       .event(.pageStateChanged(.accessCodeRequired)))
        XCTAssertFalse(flow.isFinished)
    }

    func testReturnMatches() throws {
        let completed = ReturnURLMatch(url: try XCTUnwrap(URL(string: "https://e.com/?session_id=sr_1&signer_id=sgr_1&status=completed")))
        var flow = SigningFlow()
        guard case .finish(.signed(let outcome)) = flow.apply(returnMatch: completed) else {
            return XCTFail("expected signed")
        }
        XCTAssertEqual(outcome.detection, .returnURL)
        XCTAssertEqual(outcome.reference, SigningReference(signatureRequestID: "sr_1", signerID: "sgr_1"))
        XCTAssertEqual(outcome.returnURL, completed.url)

        var plain = SigningFlow()
        let embedReturn = ReturnURLMatch(url: try XCTUnwrap(URL(string: "https://e.com/done")))
        guard case .finish(.signed) = plain.apply(returnMatch: embedReturn) else {
            return XCTFail("expected signed for a plain return URL")
        }

        var declined = SigningFlow()
        let declinedMatch = ReturnURLMatch(url: try XCTUnwrap(URL(string: "https://e.com/?status=declined")))
        guard case .finish(.declined) = declined.apply(returnMatch: declinedMatch) else {
            return XCTFail("expected declined")
        }

        var odd = SigningFlow()
        let oddMatch = ReturnURLMatch(url: try XCTUnwrap(URL(string: "https://e.com/?status=paused")))
        XCTAssertEqual(odd.apply(returnMatch: oddMatch), .finish(.failed(.unexpectedReturnStatus("paused"))))
    }

    func testCancel() {
        var canceled = SigningFlow()
        XCTAssertEqual(canceled.cancel(showingError: nil), .finish(.canceled))
        var failed = SigningFlow()
        XCTAssertEqual(failed.cancel(showingError: .timedOut), .finish(.failed(.timedOut)))
        var invalid = SigningFlow()
        XCTAssertEqual(invalid.fail(.invalidURL(.missingURL)), .finish(.failed(.invalidURL(.missingURL))))
        XCTAssertEqual(invalid.fail(.timedOut), .ignored)
    }
}
