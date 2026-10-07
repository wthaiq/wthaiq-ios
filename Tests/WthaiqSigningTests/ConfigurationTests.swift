import XCTest
@testable import WthaiqSigning

final class ConfigurationTests: XCTestCase {
    func testDefaults() {
        let configuration = WthaiqSigningConfiguration()
        XCTAssertEqual(configuration.language, .automatic)
        XCTAssertEqual(configuration.allowedHosts, ["wthaiq.com", "www.wthaiq.com"])
        XCTAssertEqual(configuration.allowedHosts, WthaiqSigningSDK.platformHosts)
        XCTAssertTrue(configuration.returnURLs.isEmpty)
        XCTAssertTrue(configuration.showsCloseButton)
        XCTAssertEqual(configuration.timeout, 30)
        XCTAssertEqual(configuration.dismissal, .automatic(after: 1.5))
        XCTAssertEqual(configuration.identityVerification, .followPlatform)
        XCTAssertTrue(configuration.identityVerificationHosts.isEmpty)
        XCTAssertTrue(configuration.detectsPlatformReturnNavigation)
        XCTAssertTrue(configuration.usesEphemeralWebsiteData)
        XCTAssertFalse(configuration.allowsInsecureLocalHosts)
        XCTAssertFalse(configuration.isInspectable)
        XCTAssertEqual(configuration.appearance, WthaiqSigningConfiguration.Appearance())
        XCTAssertEqual(configuration.appearance.tintColor, .brand)
        XCTAssertEqual(configuration.appearance.interfaceStyle, .system)
        XCTAssertNil(configuration.appearance.title)
        XCTAssertTrue(configuration.appearance.showsHeader)
        XCTAssertTrue(configuration.appearance.showsProgressBar)
        XCTAssertTrue(configuration.appearance.confirmsBeforeClosing)
    }

    func testTimeoutIsClamped() {
        XCTAssertEqual(WthaiqSigningConfiguration(timeout: 1).effectiveTimeout, 5)
        XCTAssertEqual(WthaiqSigningConfiguration(timeout: 45).effectiveTimeout, 45)
        XCTAssertEqual(WthaiqSigningConfiguration(timeout: 9_999).effectiveTimeout, 120)
        XCTAssertEqual(WthaiqSigningConfiguration(timeout: .nan).effectiveTimeout, 30)
        XCTAssertEqual(WthaiqSigningConfiguration(timeout: .infinity).effectiveTimeout, 30)
    }

    func testDismissalDelay() {
        XCTAssertEqual(WthaiqSigningConfiguration().dismissalDelay, 1.5)
        XCTAssertNil(WthaiqSigningConfiguration(dismissal: .manual).dismissalDelay)
        XCTAssertEqual(WthaiqSigningConfiguration(dismissal: .automatic(after: -3)).dismissalDelay, 0)
        XCTAssertEqual(WthaiqSigningConfiguration(dismissal: .automatic(after: 600)).dismissalDelay, 30)
        XCTAssertEqual(WthaiqSigningConfiguration(dismissal: .automatic(after: .nan)).dismissalDelay, 1.5)
    }

    func testAddAllowedHostNormalizes() {
        var configuration = WthaiqSigningConfiguration()
        configuration.addAllowedHost(" Sign.Example.COM. ")
        configuration.addAllowedHost("   ")
        XCTAssertTrue(configuration.allowedHosts.contains("sign.example.com"))
        XCTAssertEqual(configuration.allowedHosts.count, 3)
    }

    func testLanguageResolution() {
        XCTAssertEqual(ResolvedLanguage.resolve(.arabic, preferredLanguages: ["en"]), .arabic)
        XCTAssertEqual(ResolvedLanguage.resolve(.english, preferredLanguages: ["ar"]), .english)
        XCTAssertEqual(ResolvedLanguage.resolve(.automatic, preferredLanguages: ["ar-EG", "en"]), .arabic)
        XCTAssertEqual(ResolvedLanguage.resolve(.automatic, preferredLanguages: ["AR"]), .arabic)
        XCTAssertEqual(ResolvedLanguage.resolve(.automatic, preferredLanguages: ["en-US", "ar"]), .english)
        XCTAssertEqual(ResolvedLanguage.resolve(.automatic, preferredLanguages: []), .english)
        XCTAssertTrue(ResolvedLanguage.arabic.isRightToLeft)
        XCTAssertFalse(ResolvedLanguage.english.isRightToLeft)
    }

    func testVersionConstants() {
        XCTAssertEqual(WthaiqSigningSDK.version, "1.0.0")
        XCTAssertEqual(WthaiqSigningSDK.apiVersion, "2026-07-01")
    }
}

final class SigningColorTests: XCTestCase {
    func testBrandColor() {
        XCTAssertEqual(SigningColor.brand.light, 0x121AB0)
        XCTAssertEqual(SigningColor.brand.dark, 0x8B91F7)
        XCTAssertEqual(SigningColor(hex: 0xFF121AB0).light, 0x121AB0)
    }

    func testBrandContrast() {
        XCTAssertGreaterThan(SigningColor.contrastRatio(0x121AB0, 0xFFFFFF), 11)
        XCTAssertGreaterThan(SigningColor.contrastRatio(0x8B91F7, 0x000000), 7)
        XCTAssertEqual(SigningColor.contrastRatio(0xFFFFFF, 0xFFFFFF), 1, accuracy: 0.0001)
        XCTAssertEqual(SigningColor.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.0001)
    }

    func testForegroundChoice() {
        XCTAssertEqual(SigningColor.foreground(on: 0x121AB0), 0xFFFFFF)
        XCTAssertEqual(SigningColor.foreground(on: 0x8B91F7), 0x0B0B0B)
        XCTAssertEqual(SigningColor.foreground(on: 0xFFD60A), 0x0B0B0B)
        XCTAssertEqual(SigningColor.foreground(on: 0x000000), 0xFFFFFF)
    }
}

final class StringsTests: XCTestCase {
    private func allStrings(_ strings: SigningStrings) -> [String] {
        [
            strings.title, strings.close, strings.loading, strings.retry, strings.confirmTitle, strings.confirmMessage,
            strings.confirmLeave, strings.confirmStay, strings.announceSigned, strings.announceDeclined, strings.okay,
            strings.cancel, strings.offlineTitle, strings.offlineMessage, strings.timeoutTitle, strings.timeoutMessage,
            strings.serverTitle, strings.serverMessage, strings.genericTitle, strings.genericMessage,
            strings.invalidLinkTitle, strings.invalidLinkMessage, strings.crashTitle, strings.crashMessage
        ]
    }

    func testEveryStringExistsInBothLanguages() {
        let arabic = SigningStrings.make(.arabic)
        let english = SigningStrings.make(.english)
        XCTAssertTrue(arabic.isRightToLeft)
        XCTAssertFalse(english.isRightToLeft)
        let arabicValues = allStrings(arabic)
        let englishValues = allStrings(english)
        XCTAssertEqual(arabicValues.count, englishValues.count)
        for (arabicText, englishText) in zip(arabicValues, englishValues) {
            XCTAssertFalse(arabicText.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(englishText.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertNotEqual(arabicText, englishText)
            XCTAssertNotNil(arabicText.range(of: "\\p{Arabic}", options: .regularExpression), arabicText)
        }
    }

    func testErrorTextMapping() {
        let strings = SigningStrings.make(.english)
        XCTAssertEqual(strings.errorText(for: .network(code: NSURLErrorNotConnectedToInternet, message: "")).title,
                       strings.offlineTitle)
        XCTAssertEqual(strings.errorText(for: .network(code: NSURLErrorBadServerResponse, message: "")).title,
                       strings.genericTitle)
        XCTAssertEqual(strings.errorText(for: .timedOut).title, strings.timeoutTitle)
        XCTAssertEqual(strings.errorText(for: .httpStatus(503)).title, strings.serverTitle)
        XCTAssertEqual(strings.errorText(for: .invalidURL(.missingToken)).title, strings.invalidLinkTitle)
        XCTAssertEqual(strings.errorText(for: .webContentTerminated).title, strings.crashTitle)
    }

    func testSymbolNames() {
        XCTAssertEqual(SigningStrings.symbolName(for: .network(code: NSURLErrorNetworkConnectionLost, message: "")),
                       "wifi.exclamationmark")
        XCTAssertEqual(SigningStrings.symbolName(for: .invalidURL(.missingURL)), "link")
        XCTAssertEqual(SigningStrings.symbolName(for: .httpStatus(500)), "exclamationmark.triangle")
    }
}
