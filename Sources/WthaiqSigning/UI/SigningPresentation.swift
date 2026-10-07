#if os(iOS)
import UIKit

public extension WthaiqSigningViewController {
    /// Presents the signing view full screen over `presenter` (or over whatever it is already presenting),
    /// waits until the session has ended and the view has been dismissed, and returns the result.
    ///
    /// ```swift
    /// let result = await WthaiqSigningViewController.present(url: signingURL, from: self)
    /// ```
    static func present(
        url: URL,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration(),
        from presenter: UIViewController,
        animated: Bool = true
    ) async -> SigningResult {
        let controller = WthaiqSigningViewController(url: url, configuration: configuration)
        controller.modalPresentationStyle = .fullScreen
        let session = SigningPresentationSession(animated: animated)
        controller.delegate = session
        controller.didLeaveHandler = { [weak session] in
            session?.controllerDidLeave()
        }

        var host = presenter
        while let presented = host.presentedViewController, !presented.isBeingDismissed {
            host = presented
        }
        host.present(controller, animated: animated)
        return await session.waitForCompletion()
    }
}

public extension UIViewController {
    /// Presents a Wthaiq signing page full screen and returns the result once the view has been dismissed.
    func presentWthaiqSigning(
        url: URL,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration(),
        animated: Bool = true
    ) async -> SigningResult {
        await WthaiqSigningViewController.present(url: url, configuration: configuration, from: self, animated: animated)
    }
}

/// Delegate used by `WthaiqSigningViewController.present(url:configuration:from:animated:)`.
@MainActor
final class SigningPresentationSession: WthaiqSigningViewControllerDelegate {
    private let animated: Bool
    private var result: SigningResult?
    private var delivered: SigningResult?
    private var continuation: CheckedContinuation<SigningResult, Never>?
    private var isDismissing = false

    init(animated: Bool) {
        self.animated = animated
    }

    func waitForCompletion() async -> SigningResult {
        if let delivered {
            return delivered
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func signingViewController(_ controller: WthaiqSigningViewController, didFinishWith result: SigningResult) {
        self.result = result
    }

    func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController) {
        guard !isDismissing else { return }
        isDismissing = true
        guard controller.presentingViewController != nil else {
            complete(fallback: controller.finalResult)
            return
        }
        controller.dismiss(animated: animated) { [weak self, weak controller] in
            self?.complete(fallback: controller?.finalResult)
        }
    }

    func controllerDidLeave() {
        complete(fallback: nil)
    }

    private func complete(fallback: SigningResult?) {
        guard delivered == nil else { return }
        let value = result ?? fallback ?? .canceled
        delivered = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
#endif
