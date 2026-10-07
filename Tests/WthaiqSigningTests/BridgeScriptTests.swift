#if canImport(JavaScriptCore)
import JavaScriptCore
import XCTest
@testable import WthaiqSigning

/// Runs the injected script in JavaScriptCore against a minimal stand-in for `window` and `document`.
final class BridgeScriptTests: XCTestCase {
    private struct Page {
        var path = "/sign.php"
        var readyState = "complete"
        var stateIcon: String?
        var signedPanel = false
        var declinedPanel = false
        var sealPending = false
        var captureInputs = 0
    }

    private func run(_ page: Page, stripCapture: Bool = false, then script: String = "") throws -> (posted: [[String: Any]], removedCapture: Int) {
        let context = try XCTUnwrap(JSContext())
        var exceptions: [String] = []
        context.exceptionHandler = { _, value in
            exceptions.append(value?.toString() ?? "unknown")
        }
        let stub = """
        var window = this;
        var posted = [];
        var removedCapture = 0;
        var listeners = {};
        window.webkit = { messageHandlers: { wthaiqSigning: { postMessage: function (body) { posted.push(JSON.stringify(body)); } } } };
        window.addEventListener = function (type, fn) { listeners[type] = fn; };
        window.location = { pathname: '\(page.path)' };
        var setInterval = function () { return 1; };
        var clearInterval = function () {};
        var iconClass = \(page.stateIcon.map { "'\($0)'" } ?? "null");
        var document = {
          readyState: '\(page.readyState)',
          documentElement: {},
          addEventListener: function () {},
          getElementById: function (id) {
            if (id === 'sign-ok') { return { style: { display: \(page.signedPanel ? "'block'" : "'none'") } }; }
            if (id === 'decline-ok') { return { style: { display: \(page.declinedPanel ? "'block'" : "'none'") } }; }
            return null;
          },
          querySelector: function (selector) {
            if (selector === '.state-page .state-icon i' && iconClass) {
              return { classList: { contains: function (name) { return name === iconClass; } } };
            }
            if (selector === 'iframe[src*="pades=auto"]' && \(page.sealPending ? "true" : "false")) { return {}; }
            return null;
          },
          querySelectorAll: function (selector) {
            var list = [];
            for (var i = 0; i < \(page.captureInputs); i++) {
              list.push({ removeAttribute: function (name) { if (name === 'capture') { removedCapture++; } } });
            }
            return list;
          }
        };
        """
        context.evaluateScript(stub)
        context.evaluateScript(BridgeScript.source(stripsCaptureAttribute: stripCapture))
        if !script.isEmpty {
            context.evaluateScript(script)
        }
        XCTAssertEqual(exceptions, [])
        let json = context.evaluateScript("JSON.stringify(posted)")?.toString() ?? "[]"
        let strings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        let posted = try strings.map { text -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        }
        let removed = context.evaluateScript("removedCapture")?.toInt32() ?? 0
        return (posted, Int(removed))
    }

    func testScriptParses() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }
        context.evaluateScript("var parsed = typeof function () {\n" + BridgeScript.source(stripsCaptureAttribute: true) + "\n};")
        XCTAssertNil(exception)
        XCTAssertEqual(context.evaluateScript("parsed")?.toString(), "function")
    }

    func testPlaceholderIsReplaced() {
        XCTAssertFalse(BridgeScript.source(stripsCaptureAttribute: true).contains("__WTHAIQ_STRIP_CAPTURE__"))
        XCTAssertTrue(BridgeScript.source(stripsCaptureAttribute: true).contains("var STRIP_CAPTURE = true;"))
        XCTAssertTrue(BridgeScript.source(stripsCaptureAttribute: false).contains("var STRIP_CAPTURE = false;"))
    }

    func testForwardsSigningPageMessages() throws {
        let dispatch = """
        listeners.message({ origin: 'https://wthaiq.com', data: { source: 'wthaiq', event: 'signed', type: 'wthaiq:signed', signature_request: 'sr_1', signer: 'sgr_1', extra: { nested: true }, count: 3 } });
        listeners.message({ origin: 'https://ads.example', data: { source: 'ads', event: 'signed' } });
        listeners.message({ origin: 'https://wthaiq.com', data: 'wthaiq:signed' });
        """
        let result = try run(Page(path: "/embed/sign/abc"), then: dispatch)
        XCTAssertEqual(result.posted.count, 1)
        let body = try XCTUnwrap(result.posted.first)
        XCTAssertEqual(body["kind"] as? String, "message")
        XCTAssertEqual(body["origin"] as? String, "https://wthaiq.com")
        let data = try XCTUnwrap(body["data"] as? [String: String])
        XCTAssertEqual(data["event"], "signed")
        XCTAssertEqual(data["signature_request"], "sr_1")
        XCTAssertEqual(data["count"], "3")
        XCTAssertNil(data["extra"])

        let signal = PageMessageDecoder.decode(body) { $0 == "https://wthaiq.com" }
        XCTAssertEqual(signal, .signed(SigningReference(signatureRequestID: "sr_1", signerID: "sgr_1"), .pageEvent))
    }

    func testReportsStatePages() throws {
        let result = try run(Page(stateIcon: "fa-clock"))
        XCTAssertEqual(result.posted.count, 1)
        XCTAssertEqual(result.posted.first?["kind"] as? String, "dom")
        XCTAssertEqual(result.posted.first?["event"] as? String, "state")
        XCTAssertEqual(result.posted.first?["state"] as? String, "expired")
    }

    func testReportsCompletionPanels() throws {
        let signed = try run(Page(signedPanel: true))
        XCTAssertEqual(signed.posted.map { $0["event"] as? String }, ["signed"])

        let declined = try run(Page(declinedPanel: true))
        XCTAssertEqual(declined.posted.map { $0["event"] as? String }, ["declined"])
    }

    func testWaitsWhileTokenSignatureIsMerged() throws {
        let result = try run(Page(signedPanel: true, sealPending: true))
        XCTAssertTrue(result.posted.isEmpty)
    }

    func testIgnoresContentOutsideTheSigningPage() throws {
        let result = try run(Page(path: "/verify", stateIcon: "fa-clock", signedPanel: true))
        XCTAssertTrue(result.posted.isEmpty)
    }

    func testWaitsForDocumentWhileLoading() throws {
        let result = try run(Page(readyState: "loading", signedPanel: true))
        XCTAssertTrue(result.posted.isEmpty)
    }

    func testStripsCaptureOnlyWhenAsked() throws {
        XCTAssertEqual(try run(Page(path: "/other", captureInputs: 2), stripCapture: true).removedCapture, 2)
        XCTAssertEqual(try run(Page(path: "/sign.php", captureInputs: 2), stripCapture: false).removedCapture, 0)
    }

    func testRunsOnlyOncePerFrame() throws {
        let again = "eval(\(try jsonString(BridgeScript.source(stripsCaptureAttribute: false))));"
        let result = try run(Page(signedPanel: true), then: again)
        XCTAssertEqual(result.posted.count, 1)
    }

    private func jsonString(_ text: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [text])
        let array = try XCTUnwrap(String(data: data, encoding: .utf8))
        return String(array.dropFirst().dropLast())
    }
}
#endif
