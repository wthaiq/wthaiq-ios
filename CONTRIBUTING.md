# Contributing

Thank you for helping improve the Wthaiq iOS library.

## Development setup

You need macOS with Xcode 15 or later (Swift 5.9+).

```bash
git clone https://github.com/wthaiq/wthaiq-ios.git
cd wthaiq-ios
open Package.swift
```

## Layout

| Path | Contents |
|---|---|
| `Sources/WthaiqSigning/Core` | Platform-independent logic (Foundation only): configuration, URL validation, return URL patterns, the navigation policy, page message decoding, the session state machine, strings and the injected script. |
| `Sources/WthaiqSigning/UI` | iOS-only code (`#if os(iOS)`): the view controller, its chrome, presentation helpers and SwiftUI support. |
| `Tests/WthaiqSigningTests` | XCTest suites. Core tests also run on a macOS host; `ViewControllerTests` runs on iOS only. |
| `Examples/WthaiqSigningDemo` | A SwiftUI demo app. Generate its project with [XcodeGen](https://github.com/yonaskolb/XcodeGen). |

Keep decisions in `Core` so they stay unit-testable; the view controller should only translate WebKit callbacks
into calls on those types.

## Checks

Run all of these before opening a pull request (CI runs the same on `macos-latest`):

```bash
swift build
swift test                                   # core logic and the injected script (JavaScriptCore)
xcodebuild test -scheme WthaiqSigning \
  -destination 'platform=iOS Simulator,name=iPhone 15'   # pick any installed iPhone simulator
swiftlint lint
cd Examples/WthaiqSigningDemo && xcodegen generate && \
  xcodebuild build -project WthaiqSigningDemo.xcodeproj -scheme WthaiqSigningDemo \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

To try the demo against a local Wthaiq server, set `allowsInsecureLocalHosts = true` in a debug build only.

## Guidelines

- Keep the public API backwards compatible within a major version, and document every public symbol.
- Add or update unit tests for every change, and update `CHANGELOG.md` under "Unreleased".
- No third-party dependencies.
- No force unwraps or `fatalError` in library code; UI code stays on the main actor.
- The SDK's text is formal Arabic and English; add both for every new string (`SigningStrings`).
- The SDK must never change what the signing page sends to the server. The injected script only observes.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org).

## Releasing

1. Update `WthaiqSigningSDK.version` and `CHANGELOG.md`.
2. Merge to `main` with CI green.
3. Tag `vX.Y.Z` and publish a GitHub release; Swift Package Manager picks up the tag.
