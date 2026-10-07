import XCTest
@testable import WthaiqSigning

final class SigningLinkTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testSigningPageURLIsValid() throws {
        let link = try SigningLink.validate(url("https://wthaiq.com/sign.php?token=abc123"))
        XCTAssertEqual(link.kind, .signingPage)
        XCTAssertEqual(link.host, "wthaiq.com")
    }

    func testEmbeddedSessionURLIsValid() throws {
        let link = try SigningLink.validate(url("https://wthaiq.com/embed/sign/0123456789abcdef0123456789abcdef0123456789abcdef"))
        XCTAssertEqual(link.kind, .embeddedSession)
    }

    func testEnglishPrefixIsAccepted() throws {
        XCTAssertEqual(try SigningLink.validate(url("https://www.wthaiq.com/en/sign.php?token=t1")).kind, .signingPage)
        XCTAssertEqual(try SigningLink.validate(url("https://wthaiq.com/en/embed/sign/ABC123")).kind, .embeddedSession)
    }

    func testOtherPathOnAllowedHostIsAccepted() throws {
        XCTAssertEqual(try SigningLink.validate(url("https://wthaiq.com/sign/0123abcd")).kind, .other)
    }

    func testPlainHTTPIsRefused() throws {
        let result = SigningLink.check(try url("http://wthaiq.com/sign.php?token=a"))
        XCTAssertEqual(result, .failure(.unsupportedScheme("http")))
    }

    func testOtherSchemesAreRefused() throws {
        XCTAssertEqual(SigningLink.check(try url("javascript:alert(1)")), .failure(.unsupportedScheme("javascript")))
        XCTAssertEqual(SigningLink.check(try url("file:///tmp/sign.php")), .failure(.unsupportedScheme("file")))
    }

    func testMissingURL() {
        XCTAssertEqual(SigningLink.check(nil), .failure(.missingURL))
    }

    func testUnknownHostIsRefused() throws {
        XCTAssertEqual(
            SigningLink.check(try url("https://wthaiq.com.evil.example/sign.php?token=a")),
            .failure(.hostNotAllowed("wthaiq.com.evil.example"))
        )
    }

    func testCustomDomainNeedsToBeAllowed() throws {
        let target = try url("https://sign.example.com/sign.php?token=a")
        XCTAssertFalse(SigningLink.isValid(target))
        var configuration = WthaiqSigningConfiguration()
        configuration.addAllowedHost("Sign.Example.com")
        XCTAssertTrue(SigningLink.isValid(target, configuration: configuration))
    }

    func testCredentialsAreRefused() throws {
        XCTAssertEqual(
            SigningLink.check(try url("https://user:pass@wthaiq.com/sign.php?token=a")),
            .failure(.containsCredentials)
        )
    }

    func testMissingTokenIsRefused() throws {
        XCTAssertEqual(SigningLink.check(try url("https://wthaiq.com/sign.php")), .failure(.missingToken))
        XCTAssertEqual(SigningLink.check(try url("https://wthaiq.com/sign.php?token=")), .failure(.missingToken))
        XCTAssertEqual(SigningLink.check(try url("https://wthaiq.com/embed/sign/")), .failure(.missingToken))
        XCTAssertEqual(SigningLink.check(try url("https://wthaiq.com/embed/sign/ab-cd")), .failure(.missingToken))
    }

    func testLocalDevelopmentNeedsTheFlag() throws {
        let local = try url("http://127.0.0.1:8782/sign.php?token=a")
        XCTAssertEqual(SigningLink.check(local), .failure(.unsupportedScheme("http")))
        let configuration = WthaiqSigningConfiguration(allowsInsecureLocalHosts: true)
        XCTAssertEqual(try SigningLink.validate(local, configuration: configuration).kind, .signingPage)
        XCTAssertEqual(
            SigningLink.check(try url("http://example.com/sign.php?token=a"), configuration: configuration),
            .failure(.unsupportedScheme("http"))
        )
    }

    func testLanguageParameterIsAdded() throws {
        let link = try SigningLink.validate(url("https://wthaiq.com/sign.php?token=a%2Bb"))
        XCTAssertEqual(link.url(for: .arabic).absoluteString, "https://wthaiq.com/sign.php?token=a%2Bb&lang=ar")
        XCTAssertEqual(link.url(for: .english).absoluteString, "https://wthaiq.com/sign.php?token=a%2Bb&lang=en")
        XCTAssertEqual(link.url(for: .automatic), link.url)
    }

    func testLanguageParameterIsAddedToPathOnlyURL() throws {
        let link = try SigningLink.validate(url("https://wthaiq.com/embed/sign/abc123"))
        XCTAssertEqual(link.url(for: .english).absoluteString, "https://wthaiq.com/embed/sign/abc123?lang=en")
    }

    func testExistingLanguageParameterIsKept() throws {
        let link = try SigningLink.validate(url("https://wthaiq.com/sign.php?token=a&lang=en"))
        XCTAssertEqual(link.url(for: .arabic), link.url)
    }

    func testErrorsHaveDescriptions() {
        let errors: [URLValidationError] = [
            .missingURL, .unsupportedScheme("http"), .missingHost, .hostNotAllowed("x"), .containsCredentials, .missingToken
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}
