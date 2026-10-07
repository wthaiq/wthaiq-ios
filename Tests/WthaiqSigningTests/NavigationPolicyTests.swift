import XCTest
@testable import WthaiqSigning

final class NavigationPolicyTests: XCTestCase {
    private let signPage = "https://wthaiq.com/sign.php?token=abc"
    private let identityHost = "verify.identity-provider.example"

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    private func request(
        _ string: String,
        mainFrame: Bool = true,
        newWindow: Bool = false,
        trigger: NavigationTrigger = .other,
        source: String? = "wthaiq.com"
    ) throws -> NavigationRequest {
        NavigationRequest(url: try url(string), isMainFrame: mainFrame, opensNewWindow: newWindow, trigger: trigger, sourceHost: source)
    }

    func testPlatformPagesAreAllowed() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request(signPage, source: nil)), .allow)
        XCTAssertEqual(policy.decide(try request("https://www.wthaiq.com/sign.php?token=abc&idv=1")), .allow)
        XCTAssertEqual(policy.decide(try request("https://wthaiq.com/sign.php?token=abc", mainFrame: false)), .allow)
        XCTAssertEqual(policy.decide(try request("https://wthaiq.com/legal/terms", trigger: .linkActivated)), .allow)
    }

    func testConfiguredReturnURLCompletes() throws {
        var configuration = WthaiqSigningConfiguration()
        configuration.addReturnURL(try url("https://shop.example.com/signing/done"))
        var policy = NavigationPolicy(configuration: configuration)
        let target = "https://shop.example.com/signing/done?session_id=sr_1&signer_id=sgr_2&status=declined"
        guard case .complete(let match) = policy.decide(try request(target)) else {
            return XCTFail("expected completion")
        }
        XCTAssertEqual(match.status, .declined)
        XCTAssertEqual(match.signatureRequestID, "sr_1")
        XCTAssertEqual(match.signerID, "sgr_2")
    }

    func testConfiguredReturnURLCompletesFromSubframeAndCustomScheme() throws {
        var configuration = WthaiqSigningConfiguration()
        configuration.returnURLs = [ReturnURLPattern(scheme: "myapp")]
        var policy = NavigationPolicy(configuration: configuration)
        guard case .complete(let match) = policy.decide(try request("myapp://signed", mainFrame: false)) else {
            return XCTFail("expected completion")
        }
        XCTAssertEqual(match.status, .unspecified)
    }

    func testPlatformReturnNavigationIsDetectedWithoutConfiguration() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let target = "https://shop.example.com/back?session_id=sr_9&signer_id=sgr_9&status=completed"
        guard case .complete(let match) = policy.decide(try request(target)) else {
            return XCTFail("expected completion")
        }
        XCTAssertEqual(match.status, .completed)
    }

    func testPlatformReturnDetectionNeedsPlatformSourceAndCanBeDisabled() throws {
        let target = "https://shop.example.com/back?session_id=sr_9&status=completed"
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request(target, trigger: .linkActivated, source: "other.example")), .openExternally(try url(target)))

        var disabled = NavigationPolicy(configuration: WthaiqSigningConfiguration(detectsPlatformReturnNavigation: false))
        XCTAssertEqual(disabled.decide(try request(target, trigger: .linkActivated)), .openExternally(try url(target)))
    }

    func testNewWindowsOpenExternally() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let final = "https://wthaiq.com/final/abc.pdf"
        XCTAssertEqual(policy.decide(try request(final, mainFrame: false, newWindow: true)), .openExternally(try url(final)))
        let outside = "https://example.org/info"
        XCTAssertEqual(policy.decide(try request(outside, newWindow: true)), .openExternally(try url(outside)))
    }

    func testTappedExternalLinkOpensInSafari() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let target = "https://example.org/privacy"
        XCTAssertEqual(policy.decide(try request(target, trigger: .linkActivated)), .openExternally(try url(target)))
    }

    func testScriptedNavigationFromPlatformStartsIdentityVerification() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let start = "https://\(identityHost)/session/abc"
        XCTAssertEqual(policy.decide(try request(start)), .allowExternalFlow(host: identityHost))
        XCTAssertTrue(policy.admittedHosts.contains(identityHost))

        let next = "https://\(identityHost)/session/abc/step2"
        XCTAssertEqual(policy.decide(try request(next, trigger: .linkActivated, source: identityHost)), .allow)
        XCTAssertEqual(policy.decide(try request(next, trigger: .formSubmitted, source: identityHost)), .allow)

        let back = "https://wthaiq.com/sign.php?token=abc&idv=1"
        XCTAssertEqual(policy.decide(try request(back, source: identityHost)), .allow)
    }

    func testAdmittedHostMayRedirectToAnotherProviderHost() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        _ = policy.decide(try request("https://\(identityHost)/start"))
        let cdn = "https://cdn.identity-provider.example/flow"
        XCTAssertEqual(policy.decide(try request(cdn, source: identityHost)), .allowExternalFlow(host: "cdn.identity-provider.example"))
    }

    func testIdentityVerificationInsideEmbeddedFrame() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let start = "https://\(identityHost)/session/abc"
        XCTAssertEqual(policy.decide(try request(start, mainFrame: false)), .allowExternalFlow(host: identityHost))
    }

    func testScriptedNavigationFromUnknownSourceIsRefused() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request("https://evil.example/", source: "ads.example")), .cancel(.hostNotAllowed))
        XCTAssertEqual(policy.decide(try request("https://evil.example/", source: nil)), .cancel(.hostNotAllowed))
    }

    func testFormSubmissionToExternalHostIsRefused() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request("https://evil.example/collect", trigger: .formSubmitted)), .cancel(.hostNotAllowed))
    }

    func testListedHostsOnlyPolicy() throws {
        let configuration = WthaiqSigningConfiguration(
            identityVerification: .listedHostsOnly,
            identityVerificationHosts: ["*.identity-provider.example"]
        )
        var policy = NavigationPolicy(configuration: configuration)
        XCTAssertEqual(policy.decide(try request("https://\(identityHost)/s")), .allow)
        XCTAssertEqual(policy.decide(try request("https://unlisted.example/s")), .cancel(.hostNotAllowed))
        XCTAssertTrue(policy.admittedHosts.isEmpty)
    }

    func testPlainHTTP() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request("http://wthaiq.com/sign.php?token=a")), .cancel(.insecureConnection))
        let tapped = "http://example.org/"
        XCTAssertEqual(policy.decide(try request(tapped, trigger: .linkActivated)), .openExternally(try url(tapped)))

        var local = NavigationPolicy(configuration: WthaiqSigningConfiguration(allowsInsecureLocalHosts: true))
        XCTAssertEqual(local.decide(try request("http://127.0.0.1:8782/sign.php?token=a", source: nil)), .allow)
    }

    func testSystemSchemes() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let mail = "mailto:support@wthaiq.com"
        XCTAssertEqual(policy.decide(try request(mail, trigger: .linkActivated)), .openExternally(try url(mail)))
        XCTAssertEqual(policy.decide(try request(mail)), .cancel(.unsupportedScheme))
        let phone = "tel:+201000000000"
        XCTAssertEqual(policy.decide(try request(phone, newWindow: true)), .openExternally(try url(phone)))
    }

    func testOtherSchemes() throws {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertEqual(policy.decide(try request("about:blank")), .allow)
        XCTAssertEqual(policy.decide(try request("about:srcdoc", mainFrame: false)), .allow)
        XCTAssertEqual(policy.decide(try request("data:text/html,hi", mainFrame: false)), .allow)
        XCTAssertEqual(policy.decide(try request("data:text/html,hi")), .cancel(.unsupportedScheme))
        XCTAssertEqual(policy.decide(try request("blob:https://wthaiq.com/1")), .cancel(.unsupportedScheme))
        XCTAssertEqual(policy.decide(try request("javascript:void(0)")), .cancel(.unsupportedScheme))
        XCTAssertEqual(policy.decide(try request("file:///etc/hosts")), .cancel(.unsupportedScheme))
        XCTAssertEqual(policy.decide(try request("otherapp://open", trigger: .linkActivated)), .cancel(.unsupportedScheme))
    }

    func testAfterFinishingExternalNavigationIsRefused() throws {
        var configuration = WthaiqSigningConfiguration()
        configuration.addReturnURL(try url("https://shop.example.com/done"))
        var policy = NavigationPolicy(configuration: configuration)
        policy.markFinished()
        XCTAssertEqual(policy.decide(try request("https://shop.example.com/done")), .cancel(.finished))
        XCTAssertEqual(policy.decide(try request("https://shop.example.com/back?session_id=sr_1&status=completed")), .cancel(.finished))
        XCTAssertEqual(policy.decide(try request("https://\(identityHost)/x")), .cancel(.finished))
        XCTAssertEqual(policy.decide(try request(signPage)), .allow)
        let pdf = "https://wthaiq.com/final/x.pdf"
        XCTAssertEqual(policy.decide(try request(pdf, newWindow: true)), .openExternally(try url(pdf)))
    }

    func testMediaCapture() {
        var policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        let both = UsageDescriptions(camera: true, microphone: true)
        let none = UsageDescriptions(camera: false, microphone: false)
        XCTAssertTrue(policy.allowsMediaCapture(.camera, scheme: "https", host: "wthaiq.com", usage: both))
        XCTAssertFalse(policy.allowsMediaCapture(.camera, scheme: "https", host: "wthaiq.com", usage: none))
        XCTAssertFalse(policy.allowsMediaCapture(.cameraAndMicrophone, scheme: "https", host: "wthaiq.com",
                                                 usage: UsageDescriptions(camera: true, microphone: false)))
        XCTAssertFalse(policy.allowsMediaCapture(.camera, scheme: "http", host: "wthaiq.com", usage: both))
        XCTAssertFalse(policy.allowsMediaCapture(.camera, scheme: "https", host: identityHost, usage: both))
        if let start = URL(string: "https://\(identityHost)/s") {
            _ = policy.decide(NavigationRequest(url: start, sourceHost: "wthaiq.com"))
        }
        XCTAssertTrue(policy.allowsMediaCapture(.microphone, scheme: "https", host: identityHost, usage: both))
    }

    func testPlatformOriginChecks() {
        let policy = NavigationPolicy(configuration: WthaiqSigningConfiguration())
        XCTAssertTrue(policy.isPlatformOrigin("https://wthaiq.com"))
        XCTAssertTrue(policy.isPlatformOrigin("https://www.wthaiq.com:443"))
        XCTAssertFalse(policy.isPlatformOrigin("http://wthaiq.com"))
        XCTAssertFalse(policy.isPlatformOrigin("https://evil.example"))
        XCTAssertFalse(policy.isPlatformOrigin("null"))
        XCTAssertFalse(policy.isPlatformOrigin(""))
        XCTAssertTrue(policy.isPlatformFrame(scheme: "HTTPS", host: "wthaiq.com"))
        XCTAssertFalse(policy.isPlatformFrame(scheme: "https", host: identityHost))
    }
}
