import XCTest
@testable import WthaiqSigning

final class ReturnURLTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testPatternFromURL() throws {
        let pattern = try XCTUnwrap(ReturnURLPattern(url: url("HTTPS://Example.COM/signing/done/?x=1#top")))
        XCTAssertEqual(pattern.scheme, "https")
        XCTAssertEqual(pattern.host, "example.com")
        XCTAssertEqual(pattern.pathPrefix, "/signing/done")
        XCTAssertEqual(pattern.description, "https://example.com/signing/done")
    }

    func testPatternMatchesPathPrefixOnSegmentBoundary() throws {
        let pattern = try XCTUnwrap(ReturnURLPattern(string: "https://example.com/signing/done"))
        XCTAssertTrue(pattern.matches(try url("https://example.com/signing/done")))
        XCTAssertTrue(pattern.matches(try url("https://EXAMPLE.com/signing/done/")))
        XCTAssertTrue(pattern.matches(try url("https://example.com/signing/done/step?status=completed")))
        XCTAssertTrue(pattern.matches(try url("https://example.com:8443/signing/done")))
        XCTAssertFalse(pattern.matches(try url("https://example.com/signing/doneX")))
        XCTAssertFalse(pattern.matches(try url("https://example.com/signing")))
        XCTAssertFalse(pattern.matches(try url("http://example.com/signing/done")))
        XCTAssertFalse(pattern.matches(try url("https://other.example.com/signing/done")))
    }

    func testRootPatternMatchesAnyPathOnHost() throws {
        let pattern = try XCTUnwrap(ReturnURLPattern(string: "https://example.com"))
        XCTAssertEqual(pattern.pathPrefix, "/")
        XCTAssertTrue(pattern.matches(try url("https://example.com/anything?status=declined")))
        XCTAssertFalse(pattern.matches(try url("https://example.org/")))
    }

    func testCustomSchemeWithoutHostMatchesAnyHost() throws {
        let pattern = ReturnURLPattern(scheme: "MyApp")
        XCTAssertTrue(pattern.matches(try url("myapp://signing/done?status=completed")))
        XCTAssertFalse(pattern.matches(try url("otherapp://signing/done")))
    }

    func testWebPatternWithoutHostMatchesNothing() throws {
        let pattern = ReturnURLPattern(scheme: "https")
        XCTAssertNil(pattern.host)
        XCTAssertFalse(pattern.matches(try url("https://example.com/")))
        XCTAssertNil(ReturnURLPattern(string: "https:///nohost"))
    }

    func testConfigurationAddReturnURL() throws {
        var configuration = WthaiqSigningConfiguration()
        XCTAssertTrue(configuration.addReturnURL(try url("https://example.com/done")))
        XCTAssertTrue(configuration.addReturnURL(try url("https://example.com/done")))
        XCTAssertEqual(configuration.returnURLs.count, 1)
        XCTAssertTrue(configuration.addReturnURL(try url("myapp://done")))
        XCTAssertEqual(configuration.returnURLs.count, 2)
    }

    func testMatchParsesPlatformQuery() throws {
        let match = ReturnURLMatch(url: try url(
            "https://example.com/done?order=7&session_id=sr_4f375a20cb1a4dda8f0f&signer_id=sgr_71769e6564cbb1d00ccc&status=completed"
        ))
        XCTAssertEqual(match.status, .completed)
        XCTAssertEqual(match.signatureRequestID, "sr_4f375a20cb1a4dda8f0f")
        XCTAssertEqual(match.signerID, "sgr_71769e6564cbb1d00ccc")
        XCTAssertTrue(match.isPlatformReturnTarget)
    }

    func testMatchStatuses() throws {
        XCTAssertEqual(ReturnURLMatch(url: try url("https://e.com/?status=DECLINED")).status, .declined)
        XCTAssertEqual(ReturnURLMatch(url: try url("https://e.com/")).status, .unspecified)
        XCTAssertEqual(ReturnURLMatch(url: try url("https://e.com/?status=")).status, .unspecified)
        XCTAssertEqual(ReturnURLMatch(url: try url("https://e.com/?status=expired")).status, .other("expired"))
    }

    func testPlatformReturnTargetNeedsRequestIdAndKnownStatus() throws {
        XCTAssertFalse(ReturnURLMatch(url: try url("https://e.com/?status=completed")).isPlatformReturnTarget)
        XCTAssertFalse(ReturnURLMatch(url: try url("https://e.com/?session_id=abc&status=completed")).isPlatformReturnTarget)
        XCTAssertFalse(ReturnURLMatch(url: try url("https://e.com/?session_id=sr_1&status=other")).isPlatformReturnTarget)
        XCTAssertTrue(ReturnURLMatch(url: try url("https://e.com/?session_id=sr_1&status=declined")).isPlatformReturnTarget)
    }

    func testOverlongValuesAreIgnored() throws {
        let long = String(repeating: "a", count: 201)
        let match = ReturnURLMatch(url: try url("https://e.com/?session_id=sr_\(long)&status=completed"))
        XCTAssertNil(match.signatureRequestID)
    }
}
