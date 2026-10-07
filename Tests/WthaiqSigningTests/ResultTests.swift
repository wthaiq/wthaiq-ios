import XCTest
@testable import WthaiqSigning

final class ResultTests: XCTestCase {
    func testResultFromReturnURL() throws {
        let completed = try XCTUnwrap(URL(string: "https://e.com/done?session_id=sr_1&signer_id=sgr_1&status=completed"))
        let result = try XCTUnwrap(SigningResult(returnURL: completed))
        XCTAssertTrue(result.isSigned)
        XCTAssertEqual(result.outcome?.reference.signatureRequestID, "sr_1")
        XCTAssertEqual(result.outcome?.detection, .returnURL)
        XCTAssertEqual(result.outcome?.returnURL, completed)

        let declined = try XCTUnwrap(URL(string: "https://e.com/done?status=declined"))
        guard case .declined = try XCTUnwrap(SigningResult(returnURL: declined)) else {
            return XCTFail("expected declined")
        }

        XCTAssertNil(SigningResult(returnURL: try XCTUnwrap(URL(string: "https://e.com/done"))))
        XCTAssertNil(SigningResult(returnURL: try XCTUnwrap(URL(string: "https://e.com/done?status=maybe"))))
    }

    func testAccessors() {
        XCTAssertFalse(SigningResult.canceled.isSigned)
        XCTAssertNil(SigningResult.canceled.outcome)
        XCTAssertNil(SigningResult.expired.outcome)
        XCTAssertNil(SigningResult.failed(.timedOut).outcome)
        let outcome = SigningOutcome(detection: .pageContent, wasAlreadyFinal: true)
        XCTAssertEqual(SigningResult.declined(outcome).outcome, outcome)
        XCTAssertFalse(SigningResult.declined(outcome).isSigned)
        XCTAssertTrue(SigningReference.unknown.isEmpty)
        XCTAssertFalse(SigningReference(signerID: "sgr_1").isEmpty)
    }

    func testErrorProperties() {
        XCTAssertTrue(WthaiqSigningError.timedOut.isRetryable)
        XCTAssertTrue(WthaiqSigningError.httpStatus(503).isRetryable)
        XCTAssertTrue(WthaiqSigningError.webContentTerminated.isRetryable)
        XCTAssertTrue(WthaiqSigningError.network(code: NSURLErrorNotConnectedToInternet, message: "").isRetryable)
        XCTAssertFalse(WthaiqSigningError.invalidURL(.missingURL).isRetryable)
        XCTAssertFalse(WthaiqSigningError.linkUnavailable(.canceled).isRetryable)
        XCTAssertTrue(WthaiqSigningError.network(code: NSURLErrorNotConnectedToInternet, message: "").isOffline)
        XCTAssertFalse(WthaiqSigningError.network(code: NSURLErrorBadURL, message: "").isOffline)
        XCTAssertFalse(WthaiqSigningError.timedOut.isOffline)

        let all: [WthaiqSigningError] = [
            .invalidURL(.missingHost), .network(code: -1, message: "x"), .timedOut, .httpStatus(500),
            .linkUnavailable(.notFound), .pageError("x"), .webContentTerminated, .unexpectedReturnStatus("x")
        ]
        for error in all {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    func testPageStateFinality() {
        let open: Set<SigningPageState> = [.notYourTurn, .accessCodeRequired, .identityUnavailable]
        for state in SigningPageState.allCases {
            XCTAssertEqual(state.isFinal, !open.contains(state), state.rawValue)
        }
    }
}

final class LoadFailureTests: XCTestCase {
    func testCanceledAndInterruptedLoadsAreNotFailures() {
        XCTAssertNil(LoadFailure.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertNil(LoadFailure.classify(NSError(domain: "WebKitErrorDomain", code: 102)))
        XCTAssertNil(LoadFailure.classify(NSError(domain: "WebKitErrorDomain", code: 204)))
    }

    func testTimeoutsAndNetworkErrors() {
        XCTAssertEqual(LoadFailure.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)), .timedOut)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                              userInfo: [NSLocalizedDescriptionKey: "offline"])
        XCTAssertEqual(LoadFailure.classify(offline), .network(code: NSURLErrorNotConnectedToInternet, message: "offline"))
        let other = NSError(domain: "WebKitErrorDomain", code: 101, userInfo: [NSLocalizedDescriptionKey: "bad"])
        XCTAssertEqual(LoadFailure.classify(other), .network(code: 101, message: "bad"))
    }

    func testFailingURL() throws {
        let target = try XCTUnwrap(URL(string: "https://wthaiq.com/sign.php?token=a"))
        XCTAssertEqual(LoadFailure.failingURL(of: NSError(domain: NSURLErrorDomain, code: -1,
                                                          userInfo: [NSURLErrorFailingURLErrorKey: target])), target)
        XCTAssertEqual(LoadFailure.failingURL(of: NSError(domain: NSURLErrorDomain, code: -1,
                                                          userInfo: [NSURLErrorFailingURLStringErrorKey: target.absoluteString])), target)
        XCTAssertNil(LoadFailure.failingURL(of: NSError(domain: NSURLErrorDomain, code: -1)))
    }

    func testBlockingStatuses() {
        XCTAssertTrue(LoadFailure.isBlockingStatus(429))
        XCTAssertTrue(LoadFailure.isBlockingStatus(500))
        XCTAssertTrue(LoadFailure.isBlockingStatus(503))
        XCTAssertFalse(LoadFailure.isBlockingStatus(200))
        XCTAssertFalse(LoadFailure.isBlockingStatus(404))
        XCTAssertFalse(LoadFailure.isBlockingStatus(403))
    }

    func testUsageDescriptionsFromBundle() {
        let usage = UsageDescriptions.read(from: Bundle(for: LoadFailureTests.self))
        XCTAssertFalse(usage.camera)
        XCTAssertFalse(usage.microphone)
    }
}
