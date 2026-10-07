#if os(iOS)
import UIKit
import WebKit
import XCTest
@testable import WthaiqSigning

final class ViewControllerTests: XCTestCase {
    private final class RecordingDelegate: WthaiqSigningViewControllerDelegate {
        var results: [SigningResult] = []
        var dismissals = 0

        func signingViewController(_ controller: WthaiqSigningViewController, didFinishWith result: SigningResult) {
            results.append(result)
        }

        func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController) {
            dismissals += 1
        }
    }

    /// WebKit only calls delegate methods that are visible to the Objective-C runtime. A signature that
    /// drifts from the SDK headers would compile but silently never be called, so check the selectors.
    @MainActor
    func testDelegateMethodsAreVisibleToWebKit() throws {
        let controller = WthaiqSigningViewController(url: try XCTUnwrap(URL(string: "https://wthaiq.com/sign.php?token=a")))
        let selectors = [
            "webView:decidePolicyForNavigationAction:decisionHandler:",
            "webView:decidePolicyForNavigationResponse:decisionHandler:",
            "webView:didStartProvisionalNavigation:",
            "webView:didCommitNavigation:",
            "webView:didFinishNavigation:",
            "webView:didFailNavigation:withError:",
            "webView:didFailProvisionalNavigation:withError:",
            "webViewWebContentProcessDidTerminate:",
            "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:",
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:",
            "presentationControllerDidAttemptToDismiss:"
        ]
        for name in selectors {
            XCTAssertTrue(controller.responds(to: NSSelectorFromString(name)), name)
        }
        let proxy = ScriptMessageProxy(owner: controller)
        XCTAssertTrue(proxy.responds(to: NSSelectorFromString("userContentController:didReceiveScriptMessage:")))
    }

    @MainActor
    func testInvalidURLFinishesImmediately() async throws {
        let target = try XCTUnwrap(URL(string: "https://example.com/sign.php?token=a"))
        let controller = WthaiqSigningViewController(url: target)
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.loadViewIfNeeded()

        let expected = SigningResult.failed(.invalidURL(.hostNotAllowed("example.com")))
        XCTAssertEqual(controller.finalResult, expected)
        XCTAssertEqual(delegate.results, [expected])
        let awaited = await controller.result()
        XCTAssertEqual(awaited, expected)
    }

    @MainActor
    func testCancelFinishesOnce() async throws {
        let controller = WthaiqSigningViewController(url: try XCTUnwrap(URL(string: "https://wthaiq.com/sign.php?token=a")))
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.cancel()
        controller.cancel()
        XCTAssertEqual(delegate.results, [.canceled])
        let awaited = await controller.result()
        XCTAssertEqual(awaited, .canceled)
    }

    @MainActor
    func testValidURLCreatesWebView() throws {
        let controller = WthaiqSigningViewController(url: try XCTUnwrap(URL(string: "https://wthaiq.com/sign.php?token=a")))
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.finalResult)
        XCTAssertTrue(controller.view.subviews.contains { $0 is WKWebView })
        controller.cancel()
    }

    @MainActor
    func testRightToLeftLayoutForArabic() throws {
        let configuration = WthaiqSigningConfiguration(language: .arabic)
        let controller = WthaiqSigningViewController(url: try XCTUnwrap(URL(string: "https://wthaiq.com/sign.php?token=a")),
                                                     configuration: configuration)
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.view.semanticContentAttribute, .forceRightToLeft)
        controller.cancel()
    }

    @MainActor
    func testDynamicBrandColor() {
        let color = SigningColor.brand.uiColor
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(SigningColor.hex(of: light), 0x121AB0)
        XCTAssertEqual(SigningColor.hex(of: dark), 0x8B91F7)
        XCTAssertEqual(SigningColor(color), .brand)
    }
}
#endif
