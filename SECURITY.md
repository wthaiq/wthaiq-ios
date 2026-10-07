# Security Policy

## Reporting a vulnerability

Please report security issues privately by email to **support@wthaiq.com** with the subject
"Security: wthaiq-ios". Do not open a public GitHub issue, pull request or discussion for a vulnerability.

Include a description of the issue, the affected version, the iOS version and device, steps to reproduce and, if
possible, a proof of concept. We acknowledge reports within three business days and keep you informed until the
issue is fixed.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.x     | Yes       |

## Using the SDK safely

- **Never ship a Wthaiq API key in an app.** Create signing links on your server with a secret key (`sk_…`) and send
  only the signing URL to the app. Anything inside an app binary can be extracted.
- A signing URL lets its holder sign as that signer. Send it only to the signer it belongs to, over TLS, just before
  presenting it, and never log it.
- Treat the result the SDK reports as a signal for your interface. Confirm signatures on your server with verified
  webhooks (`signer.signed`, `signature_request.completed`) or `GET /signature_requests/{id}` before acting on them.
- Keep `allowedHosts` limited to `wthaiq.com`, `www.wthaiq.com` and your own custom signing domain.
- Leave `allowsInsecureLocalHosts` and `isInspectable` off in release builds.
- Keep `usesEphemeralWebsiteData` on (the default) on shared or managed devices.

## What the SDK enforces

- Signing URLs must be `https`, without credentials, on an allowed host.
- Only Wthaiq pages, your return URLs (which end the session) and the identity verification step load in the signing
  view; other links open in Safari and unknown schemes are refused.
- Page events are accepted only from Wthaiq frames and origins, through a script that runs isolated from page scripts.
- Camera and microphone access is granted only to trusted pages, and only when the app declares the usage descriptions.
