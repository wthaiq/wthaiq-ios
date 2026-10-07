# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.0.0] - 2026-10-07

First release. Targets Wthaiq API version `2026-07-01`; iOS 15+, Swift 5.9+.

### Added

- `WthaiqSigningViewController` with a delegate, `result() async`, `cancel()`, `reload()` and
  `dismissFromContainer()`; works presented, pushed or embedded.
- `presentWthaiqSigning(url:configuration:animated:)` on `UIViewController` and
  `WthaiqSigningViewController.present(url:configuration:from:animated:)`, returning the result after dismissal.
- SwiftUI: the `.wthaiqSigning(isPresented:url:configuration:onEvent:onResult:)` modifier and `WthaiqSigningSheet`.
- `SigningResult` (`signed`, `declined`, `canceled`, `expired`, `failed`) with `SigningOutcome` (request and signer
  ids, detection source, return URL, already-final flag, reason) and typed `WthaiqSigningError`.
- `SigningEvent` stream: page loaded, viewed, page state changes, identity verification started, external link
  opened, navigation blocked, load failed, unknown page messages.
- Completion detection without an API key: return URLs (configured or the page's own return navigation), embedded
  page events, and page content on plain signing links.
- `WthaiqSigningConfiguration`: language, allowed hosts (custom signing domains), return URL patterns, close button,
  appearance (brand tint `#121AB0`, light/dark, title, header, progress bar, close confirmation), timeout, dismissal
  behaviour, identity verification host policy, ephemeral website data, local development switches.
- Navigation policy: Wthaiq hosts and the identity verification step load in the view; `target="_blank"` links and
  links to other sites open in Safari; `mailto:`/`tel:`/`sms:` go to the system; everything else is refused.
- Loading, retry and error screens; timeouts; recovery from a crashed web content process; JavaScript alert,
  confirm and prompt panels.
- Arabic (right to left) and English (left to right) interface text, dark mode, Dynamic Type and VoiceOver support.
- Camera and microphone requests granted only to trusted pages and only when the app declares the usage descriptions.
- `SigningLink.validate(_:configuration:)` and `SigningResult(returnURL:)` helpers.
- Privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no collected data, no required-reason APIs.

### Distribution

- Swift Package Manager only. No CocoaPods podspec: the CocoaPods trunk is becoming read-only, Xcode integrates
  packages natively, and a second channel would need its own release pipeline for no new reach.
