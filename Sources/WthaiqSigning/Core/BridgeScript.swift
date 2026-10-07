import Foundation

/// The script injected into every frame of the signing view, in an isolated content world so page scripts
/// cannot see or call the message handler.
///
/// It only observes; it never changes what the signing page sends to the server:
/// * forwards `window` messages whose `source` is `wthaiq` or `wthaiq-inner` (the embedded signing page posts
///   `viewed`, `signed`, `declined` and `error` this way — API-SPEC §8.13);
/// * on `sign.php`, reports the completion panels (`#sign-ok`, `#decline-ok`) and the "cannot sign" state
///   pages, waiting while a token signature is still being merged into the PDF;
/// * when the app has no camera usage description, removes `capture` from file inputs so iOS offers the photo
///   library instead of terminating the app.
///
/// The native side re-checks the frame and the message origin before trusting anything.
enum BridgeScript {
    static let handlerName = "wthaiqSigning"
    static let contentWorldName = "WthaiqSigning"

    static func source(stripsCaptureAttribute: Bool) -> String {
        template.replacingOccurrences(of: "__WTHAIQ_STRIP_CAPTURE__", with: stripsCaptureAttribute ? "true" : "false")
    }

    static let template = #"""
    (function () {
      'use strict';
      if (window.__wthaiqSigningBridge) { return; }
      window.__wthaiqSigningBridge = true;
      var handlers = window.webkit && window.webkit.messageHandlers;
      var handler = handlers && handlers.wthaiqSigning;
      if (!handler) { return; }
      var STRIP_CAPTURE = __WTHAIQ_STRIP_CAPTURE__;

      function send(body) {
        try { handler.postMessage(body); } catch (e) {}
      }

      function flat(data) {
        var out = {};
        var count = 0;
        for (var key in data) {
          if (!Object.prototype.hasOwnProperty.call(data, key)) { continue; }
          if (count >= 40) { break; }
          var value = data[key];
          var type = typeof value;
          if (type === 'string') {
            out[key] = value.length > 500 ? value.slice(0, 500) : value;
            count++;
          } else if (type === 'number' || type === 'boolean') {
            out[key] = String(value);
            count++;
          }
        }
        return out;
      }

      window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || typeof data !== 'object') { return; }
        if (data.source !== 'wthaiq' && data.source !== 'wthaiq-inner') { return; }
        send({ kind: 'message', origin: String(event.origin || ''), data: flat(data) });
      }, false);

      var path = String((window.location && window.location.pathname) || '');
      var isSignPage = /\/sign\.php$/i.test(path);
      var reported = {};

      function report(name, state) {
        var key = name + ':' + (state || '');
        if (reported[key]) { return; }
        reported[key] = true;
        var body = { kind: 'dom', event: name };
        if (state) { body.state = state; }
        send(body);
      }

      var STATES = [
        ['fa-circle-check', 'already_signed'],
        ['fa-circle-half-stroke', 'already_declined'],
        ['fa-clock', 'expired'],
        ['fa-file-circle-xmark', 'canceled'],
        ['fa-triangle-exclamation', 'not_found'],
        ['fa-link-slash', 'missing_token'],
        ['fa-hourglass-half', 'not_your_turn'],
        ['fa-key', 'access_code'],
        ['fa-id-card', 'identity_unavailable']
      ];

      function checkStatePage() {
        var icon = document.querySelector('.state-page .state-icon i');
        if (!icon || !icon.classList) { return; }
        for (var i = 0; i < STATES.length; i++) {
          if (icon.classList.contains(STATES[i][0])) {
            report('state', STATES[i][1]);
            return;
          }
        }
      }

      var sealTimer = null;
      var sealChecks = 0;

      function sealPending() {
        return !!document.querySelector('iframe[src*="pades=auto"]');
      }

      function shown(element) {
        return !!(element && element.style && element.style.display === 'block');
      }

      function checkPanels() {
        if (shown(document.getElementById('sign-ok')) && !reported['signed:']) {
          if (!sealPending()) {
            report('signed');
          } else if (!sealTimer) {
            sealTimer = setInterval(function () {
              sealChecks++;
              if (!sealPending() || sealChecks >= 240) {
                clearInterval(sealTimer);
                sealTimer = null;
                report('signed');
              }
            }, 500);
          }
        }
        if (shown(document.getElementById('decline-ok'))) {
          report('declined');
        }
      }

      function stripCapture() {
        if (!STRIP_CAPTURE) { return; }
        var inputs = document.querySelectorAll('input[type="file"][capture]');
        for (var i = 0; i < inputs.length; i++) { inputs[i].removeAttribute('capture'); }
      }

      function scan() {
        stripCapture();
        if (isSignPage) {
          checkStatePage();
          checkPanels();
        }
      }

      function start() {
        if (!isSignPage && !STRIP_CAPTURE) { return; }
        scan();
        if (window.MutationObserver) {
          var observer = new window.MutationObserver(scan);
          observer.observe(document.documentElement, {
            attributes: true,
            attributeFilter: ['style', 'capture'],
            childList: true,
            subtree: true
          });
        } else {
          setInterval(scan, 700);
        }
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, false);
      } else {
        start();
      }
    })();
    """#
}
