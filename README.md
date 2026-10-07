# Wthaiq Signing for iOS

> مكتبة iOS الرسمية لمنصة وثائق للتوقيع الإلكتروني. تعرض صفحة التوقيع داخل تطبيقك بواجهة أصيلة، وتُبلغ التطبيق بنتيجة
> الجلسة: وُقِّع المستند، أو اعتذر الموقِّع، أو أُغلقت الصفحة، أو انتهت صلاحية الرابط. ولا يحمل التطبيق أيّ مفتاح سرّي
> لواجهة الربط: يُنشئ خادمك رابط التوقيع بمكتبة الخادم، ثم يسلّمه إلى التطبيق. وتدعم المكتبة العربية والإنجليزية،
> والاتجاهين من اليمين إلى اليسار ومن اليسار إلى اليمين، والوضع الداكن، وأدوات الوصول.

The official iOS library for showing [Wthaiq](https://developers.wthaiq.com) e-signature pages inside your app.
Your backend creates the signing link; the SDK presents it natively and tells your app how the session ended.

- `UIViewController`, async/await and SwiftUI APIs; iOS 15+, Swift 5.9+, no third-party dependencies.
- Signed / declined / canceled / expired / failed results, detected without polling and without an API key.
- Loading, error and retry screens, timeouts, safe areas, dark mode, Arabic (RTL) and English (LTR), VoiceOver
  and Dynamic Type.
- Navigation locked to the Wthaiq hosts, your return URL and the identity verification step; every other link
  opens in Safari.
- Camera and file pickers for ID attachments and identity verification, guarded by your Info.plist keys.

## Contents

- [Installation](#installation)
- [Security model](#security-model)
- [Quick start: SwiftUI](#quick-start-swiftui)
- [Quick start: UIKit](#quick-start-uikit)
- [Handling the result](#handling-the-result)
- [Getting a signing URL on your backend](#getting-a-signing-url-on-your-backend)
- [Configuration](#configuration)
- [Return URLs](#return-urls)
- [Language, RTL and dark mode](#language-rtl-and-dark-mode)
- [Camera, ID attachments and identity verification](#camera-id-attachments-and-identity-verification)
- [Events](#events)
- [How completion is detected](#how-completion-is-detected)
- [Troubleshooting](#troubleshooting)
- [Versioning](#versioning)
- [Support and security](#support-and-security)

## Installation

### Swift Package Manager

In Xcode choose **File → Add Package Dependencies…** and enter:

```
https://github.com/wthaiq/wthaiq-ios
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wthaiq/wthaiq-ios", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "WthaiqSigning", package: "wthaiq-ios")
    ])
]
```

Then `import WthaiqSigning`. Swift Package Manager is the only supported distribution channel; there is no
CocoaPods pod (see [CHANGELOG](CHANGELOG.md)).

## Security model

**Never put a Wthaiq API key in an app.** Anything shipped in an app binary can be extracted. Secret keys
(`sk_…`) belong on your server; publishable keys (`pk_…`) are meant for the embeddable web console and are not
needed here.

```
Your app ──(1) "I want to sign order 42"──▶ Your backend ──(2) Wthaiq API (sk_…)──▶ Wthaiq
Your app ◀─(3) signing URL───────────────── Your backend
Your app ──(4) WthaiqSigningViewController(url:) ──▶ signing page on wthaiq.com
Your backend ◀─(5) webhook signer.signed / signature_request.completed ── Wthaiq
```

1. Your app asks your backend to start signing (authenticate your user as usual).
2. Your backend creates or looks up the request with a Wthaiq server library and gets a signing URL.
3. It returns that URL to the app. Links are bearer secrets for one signer: send them only to that signer, over TLS.
4. The SDK shows the page and reports the outcome to your app.
5. Your backend confirms the outcome through webhooks (or `GET /signature_requests/{id}`). **The result the SDK
   reports drives your interface; the webhook is the proof.**

The SDK also:

- refuses URLs that are not `https`, carry credentials, or point to a host outside `allowedHosts`;
- loads only Wthaiq pages, your configured return URLs (which end the session instead of loading) and the
  identity verification step; other links open in Safari and other schemes are refused;
- trusts page events only from Wthaiq frames and origins, through a script isolated from the page;
- keeps cookies and storage in memory by default, so nothing from the session stays on the device.

## Quick start: SwiftUI

```swift
import SwiftUI
import WthaiqSigning

struct OrderView: View {
    @State private var signingURL: URL?
    @State private var isSigning = false
    @State private var message = ""

    var body: some View {
        VStack(spacing: 16) {
            Button("Sign the contract") {
                Task {
                    signingURL = try? await MyBackend.signingURL(forOrder: 42) // your API call
                    isSigning = signingURL != nil
                }
            }
            Text(message)
        }
        .wthaiqSigning(isPresented: $isSigning, url: signingURL) { result in
            switch result {
            case .signed:
                message = "Thank you. We are confirming your signature."
            case .declined:
                message = "You declined to sign."
            case .canceled:
                message = ""
            case .expired:
                message = "The link expired. Please try again."
            case .failed(let error):
                message = error.localizedDescription
            }
        }
    }
}
```

The modifier presents the signing view full screen and calls `onResult` once, after the view has been dismissed.
To control presentation yourself, put `WthaiqSigningSheet(url:configuration:onEvent:onDismissRequest:onResult:)`
inside your own `.sheet` or `.fullScreenCover`.

## Quick start: UIKit

With async/await:

```swift
import WthaiqSigning

final class OrderViewController: UIViewController {
    func signContract() {
        Task {
            guard let url = try? await MyBackend.signingURL(forOrder: 42) else { return }
            let result = await presentWthaiqSigning(url: url)
            if result.isSigned {
                showPendingConfirmation()
            }
        }
    }
}
```

`presentWthaiqSigning(url:configuration:animated:)` (also available as
`WthaiqSigningViewController.present(url:configuration:from:animated:)`) presents full screen and returns after the
view has been dismissed.

With a delegate, when you want to present, push or embed the controller yourself:

```swift
let controller = WthaiqSigningViewController(url: url, configuration: WthaiqSigningConfiguration())
controller.delegate = self
controller.modalPresentationStyle = .fullScreen
present(controller, animated: true)

extension OrderViewController: WthaiqSigningViewControllerDelegate {
    func signingViewController(_ controller: WthaiqSigningViewController, didFinishWith result: SigningResult) {
        // Called once. Update your interface; confirm on your backend.
    }

    // Optional:
    func signingViewController(_ controller: WthaiqSigningViewController, didReceive event: SigningEvent) {}
    func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController) {
        controller.dismissFromContainer()   // the default
    }
    func signingViewController(_ controller: WthaiqSigningViewController, shouldOpenExternalURL url: URL) -> Bool {
        true                                // the default: open in Safari
    }
}
```

You can also `await controller.result()`. Inside a `UINavigationController` the controller uses the navigation bar
for its title and Close button; pushed controllers are popped on dismissal.

## Handling the result

| Result | Meaning | What to do |
|---|---|---|
| `.signed(outcome)` | The signer signed (or, with `outcome.wasAlreadyFinal`, had already signed this link). | Show a "confirming" state; wait for `signer.signed` / `signature_request.completed` on your backend. |
| `.declined(outcome)` | The signer declined (or had already declined). `outcome.reason` may carry a code such as `signer_declined`. | Tell the user; the sender is notified by Wthaiq. |
| `.canceled` | The signer closed the view, or your code called `cancel()`. | Nothing was signed. Offer to resume later; the same link still works until it expires. |
| `.expired` | The link or embedded session has expired. | Ask your backend for a new link (`POST /signers/{id}/signing_session` links last 30 minutes). |
| `.failed(error)` | The session could not continue. | See `WthaiqSigningError` below. |

`outcome.reference` carries `signatureRequestID` (`sr_…`) and `signerID` (`sgr_…`) when the page or the return URL
provides them; `outcome.detection` says how the outcome was detected (`returnURL`, `pageEvent`, `pageContent`).

`WthaiqSigningError`:

| Case | When |
|---|---|
| `.invalidURL(URLValidationError)` | The URL was refused before loading (`missingURL`, `unsupportedScheme`, `missingHost`, `hostNotAllowed`, `containsCredentials`, `missingToken`). |
| `.network(code:message:)` | A `URLError` while loading (offline, DNS, TLS…); `isOffline` tells connectivity problems apart. |
| `.timedOut` | A page did not finish within `timeout`. |
| `.httpStatus(Int)` | The signing page answered 429 or 5xx. |
| `.linkUnavailable(SigningPageState)` | The sender canceled the request (`.canceled`), no request matches the link (`.notFound`), or the link has no token (`.missingToken`). |
| `.pageError(String)` | The embedded page reported another error code. |
| `.webContentTerminated` | The web content process stopped more than once. |
| `.unexpectedReturnStatus(String)` | A return URL carried an unknown `status`. |

Network, timeout, HTTP and process errors show a retry screen first; `.failed` is reported only if the signer then
closes the view. `isRetryable` tells you whether trying again may help.

If your app receives a return URL some other way (for example a universal link after signing in Safari), parse it
with `SigningResult(returnURL:)`.

## Getting a signing URL on your backend

Any of these URLs works (see the [API reference](https://developers.wthaiq.com/docs)):

| Server call | URL to send to the app | Notes |
|---|---|---|
| `POST /signers/{id}/signing_session` with `mode: "iframe"` | `signing_url` (`https://wthaiq.com/embed/sign/…`) | Best for apps: valid 30 minutes, reports signed / declined / expired events. Needs the `embed` plan feature. |
| `POST /signers/{id}/signing_session` with `mode: "redirect"` and `success_url` / `cancel_url` | `signing_url` | The page returns to your URL with `?session_id=…&signer_id=…&status=completed\|declined`. Needs `return_url`. |
| `POST /sessions` (`channel: "link"`, optional `return_url`, `language`) | `sign_url` | Workflow-based requests. |
| `POST /signature_requests` | `signers[].signing_url` | Plain links; the SDK reads the outcome from the page. |

Node.js example (the PHP and Python libraries use the same names):

```js
import Wthaiq from 'wthaiq';
const wt = new Wthaiq(process.env.WTHAIQ_API_KEY);

app.post('/wthaiq/signing-url', requireUser, async (req, res) => {
  const signerId = await signerIdFor(req.user, req.body.order_id); // your lookup
  const session = await wt.signers.createSigningSession(signerId, { mode: 'iframe' });
  res.json({ url: session.signing_url });
});
```

## Configuration

```swift
var configuration = WthaiqSigningConfiguration(
    language: .arabic,                          // .automatic (default), .arabic, .english
    showsCloseButton: true,
    appearance: .init(
        tintColor: SigningColor(light: 0x121AB0, dark: 0x8B91F7), // default: Wthaiq brand blue
        interfaceStyle: .system,                // .light, .dark
        title: nil,                             // default "Sign document" / "توقيع المستند"
        confirmsBeforeClosing: true
    ),
    timeout: 30,                                // seconds per page load (5...120)
    dismissal: .automatic(after: 1.5)           // or .manual
)
configuration.addReturnURL(URL(string: "https://example.com/signing/done")!)
configuration.addAllowedHost("sign.example.com") // your custom signing domain, if any
```

| Option | Default | Description |
|---|---|---|
| `language` | `.automatic` | SDK text language. Explicit values also add `lang=ar`/`lang=en` to the URL. `.automatic` follows your app's localization and leaves the page in the request's language. |
| `allowedHosts` | `wthaiq.com`, `www.wthaiq.com` | Hosts allowed to serve the signing page (`*.example.com` wildcards accepted). Add your custom signing domain. |
| `returnURLs` | none | Your `return_url` / `success_url` / `cancel_url` patterns. |
| `showsCloseButton` | `true` | Show Close in the title bar and on error screens. |
| `appearance` | brand blue, system style | Tint, light/dark, title, header, progress bar, close confirmation. |
| `timeout` | `30` | Seconds before the retry screen replaces a page that does not load. |
| `dismissal` | `.automatic(after: 1.5)` | After signed/declined, ask the container to dismiss after the delay (so the signer sees the confirmation), or `.manual`. Other results never dismiss automatically. |
| `identityVerification` | `.followPlatform` | `.listedHostsOnly` allows only `identityVerificationHosts` for the identity verification step. |
| `identityVerificationHosts` | none | Hosts always allowed for identity verification. |
| `detectsPlatformReturnNavigation` | `true` | Treat the page's own `?session_id=sr_…&status=…` navigation as the end of the session even if the URL is not in `returnURLs`. |
| `usesEphemeralWebsiteData` | `true` | In-memory cookies and storage. |
| `allowsInsecureLocalHosts` | `false` | Development only: allow `http` and local hosts (`localhost`, `127.0.0.1`, `*.localhost`, `*.test`). |
| `isInspectable` | `false` | Development only: allow Safari Web Inspector (iOS 16.4+). |

Use `SigningLink.validate(_:configuration:)` (or `isValid`) to check a URL before showing any interface.

## Return URLs

Set `return_url` (sessions, iframe signing sessions) or `success_url` / `cancel_url` (redirect signing sessions)
on your backend, and add the same URLs to `returnURLs`. When the page navigates to a matching URL the session ends
with the parsed result and your page is never loaded inside the signing view. Patterns match scheme, host and
path prefix; the query is ignored. Custom schemes (`ReturnURLPattern(scheme: "myapp")`) are matched too, although
the API only accepts `https` return URLs on an accepted domain.

The signing page appends `session_id`, `signer_id` and `status=completed|declined` to return URLs, except the
embedded page in iframe mode, which navigates to the plain `return_url` after signing (the SDK learns the outcome
from the page's events before that).

## Language, RTL and dark mode

- `.arabic` lays out the SDK's own interface right to left and uses formal Arabic text; `.english` uses left to right.
- `.automatic` picks Arabic when your app runs in Arabic and English otherwise. The page itself then opens in the
  language set when the request was created (`language` on `POST /sessions`).
- The SDK's interface follows the system light/dark setting (or `appearance.interfaceStyle`). The brand blue switches
  to a lighter shade in dark mode for contrast. The signing page itself is designed on a light background.
- Text uses Dynamic Type; the close button, retry screen and results are labeled and announced for VoiceOver.

## Camera, ID attachments and identity verification

Some requests ask the signer to attach a photo of an ID or to confirm their identity with the camera. Add these keys
to your app's `Info.plist`:

| Key | Needed for |
|---|---|
| `NSCameraUsageDescription` | Taking a photo of an ID attachment; identity verification. **Required** if your requests use either. |
| `NSMicrophoneUsageDescription` | Identity verification flows that ask for the microphone. Recommended. |

Choosing a photo from the library uses the system picker and needs no permission. Without
`NSCameraUsageDescription`, the SDK denies camera requests and removes the "take photo" shortcut from file inputs
instead of letting iOS terminate the app.

The identity verification step runs on an external provider's site. With the default `.followPlatform` policy the SDK
allows the host that the Wthaiq page itself opens for that step (by script or redirect), and reports
`SigningEvent.identityVerificationStarted(host:)`. Links the signer taps to any other site still open in Safari. Use
`.listedHostsOnly` with `identityVerificationHosts` for a fixed allowlist.

Signing with a USB token (`method: "token"`) needs the Wthaiq desktop signing agent and cannot be completed on a phone.

## Events

`SigningEvent` values arrive through the delegate or `onEvent`: `pageLoaded`, `viewed` (embedded page opened),
`pageStateChanged` (not this signer's turn yet, access code required, identity verification unavailable),
`identityVerificationStarted`, `externalURLOpened`, `navigationBlocked`, `loadFailed`, and `pageMessage` for page
messages this version does not know yet.

## How completion is detected

Without any secret and without polling the API, in this order:

1. **Return URL** — navigation to one of your return URLs (or the page's own return navigation).
2. **Page events** — the embedded page (`/embed/sign/…`) posts `viewed`, `signed`, `declined` and `error` events; the
   SDK receives them through a script isolated from the page and accepts them only from Wthaiq frames and origins.
3. **Page content** — on plain signing links (`/sign.php?token=…`) the SDK reads the page's confirmation panels and
   "cannot sign" screens. This is best effort; prefer embedded signing sessions or return URLs when you can.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `.failed(.invalidURL(.hostNotAllowed))` | The URL is on a custom signing domain. Add it with `addAllowedHost`. |
| `.expired` right away | Embedded signing sessions last 30 minutes. Create the link just before presenting it. |
| Your backend gets `403 plan_feature_unavailable` when creating the link | `mode: "iframe"` needs the `embed` plan feature; return URLs need `return_url`. See <https://developers.wthaiq.com/plans>. |
| The app crashes when the signer taps "Take photo" | Add `NSCameraUsageDescription` to `Info.plist`. |
| Identity verification shows a blank page with `.listedHostsOnly` | Add the provider's host to `identityVerificationHosts`, or use `.followPlatform`. |
| A link opened in Safari instead of the signing view | Expected for links the signer taps to other sites, and for `target="_blank"` links such as the signed PDF. |
| No result on plain signing links | Use an embedded signing session or a return URL; page-content detection depends on the page markup. |
| Testing against a local server | Set `allowsInsecureLocalHosts = true` in debug builds only. |

## Versioning

The SDK follows [Semantic Versioning](https://semver.org). `1.x` targets API version `2026-07-01`
(`WthaiqSigningSDK.apiVersion`). New options and events are minor releases; removing or renaming public API, or
raising the minimum iOS version, is a major release. Switch statements over `SigningEvent` should keep a `default`
branch, because new events may be added in minor releases.

## Support and security

- Documentation: <https://developers.wthaiq.com/docs>
- Support: support@wthaiq.com
- Security issues: see [SECURITY.md](SECURITY.md); please report privately to support@wthaiq.com.
- License: [MIT](LICENSE)
