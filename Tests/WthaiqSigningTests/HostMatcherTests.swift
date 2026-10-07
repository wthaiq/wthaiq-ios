import XCTest
@testable import WthaiqSigning

final class HostMatcherTests: XCTestCase {
    func testNormalizeLowercasesTrimsAndDropsTrailingDots() {
        XCTAssertEqual(HostMatcher.normalize("  WTHAIQ.com.. "), "wthaiq.com")
        XCTAssertEqual(HostMatcher.normalize("[::1]"), "::1")
        XCTAssertEqual(HostMatcher.normalize(""), "")
        XCTAssertEqual(HostMatcher.normalize("."), "")
    }

    func testExactMatch() {
        let patterns: Set<String> = ["wthaiq.com", "www.wthaiq.com"]
        XCTAssertTrue(HostMatcher.matches("wthaiq.com", patterns: patterns))
        XCTAssertTrue(HostMatcher.matches("WWW.Wthaiq.Com", patterns: patterns))
        XCTAssertTrue(HostMatcher.matches("wthaiq.com.", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("sign.wthaiq.com", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("evilwthaiq.com", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("wthaiq.com.evil.example", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("", patterns: patterns))
    }

    func testWildcardMatchesSubdomainsButNotApex() {
        let patterns: Set<String> = ["*.example.com"]
        XCTAssertTrue(HostMatcher.matches("sign.example.com", patterns: patterns))
        XCTAssertTrue(HostMatcher.matches("a.b.example.com", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("example.com", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("badexample.com", patterns: patterns))
        XCTAssertFalse(HostMatcher.matches("example.com.evil", patterns: patterns))
    }

    func testDegenerateWildcardMatchesNothing() {
        XCTAssertFalse(HostMatcher.matches("example.com", patterns: ["*."]))
        XCTAssertFalse(HostMatcher.matches("example.com", patterns: [""]))
    }

    func testLocalDevelopmentHosts() {
        for host in ["localhost", "127.0.0.1", "::1", "developers.localhost", "wthaiq.test", "LOCALHOST."] {
            XCTAssertTrue(HostMatcher.isLocalDevelopmentHost(host), host)
        }
        for host in ["wthaiq.com", "localhost.example.com", "10.0.0.1", "test"] {
            XCTAssertFalse(HostMatcher.isLocalDevelopmentHost(host), host)
        }
    }
}
