#if os(iOS)
import SwiftUI
import UIKit

/// A SwiftUI view that hosts the signing experience. Use it inside your own `.sheet` or `.fullScreenCover`,
/// or use the `.wthaiqSigning(isPresented:url:configuration:onEvent:onResult:)` modifier, which also handles
/// presentation and dismissal.
public struct WthaiqSigningSheet: View {
    private let url: URL?
    private let configuration: WthaiqSigningConfiguration
    private let onEvent: ((SigningEvent) -> Void)?
    private let onDismissRequest: (() -> Void)?
    private let onResult: (SigningResult) -> Void

    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - url: The signing URL from your backend. `nil` shows the invalid-link screen.
    ///   - configuration: Session options.
    ///   - onEvent: Informational events.
    ///   - onDismissRequest: Called when the signer taps Close or the automatic dismissal delay elapses.
    ///     When `nil`, the sheet dismisses itself with the environment's `dismiss` action.
    ///   - onResult: Called once when the session ends.
    public init(
        url: URL?,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration(),
        onEvent: ((SigningEvent) -> Void)? = nil,
        onDismissRequest: (() -> Void)? = nil,
        onResult: @escaping (SigningResult) -> Void
    ) {
        self.url = url
        self.configuration = configuration
        self.onEvent = onEvent
        self.onDismissRequest = onDismissRequest
        self.onResult = onResult
    }

    public var body: some View {
        let dismissAction = dismiss
        let requestDismissal = onDismissRequest
        SigningControllerRepresentable(
            url: url,
            configuration: configuration,
            onEvent: onEvent,
            onResult: onResult,
            onDismissRequest: {
                if let requestDismissal {
                    requestDismissal()
                } else {
                    dismissAction()
                }
            }
        )
        .ignoresSafeArea()
    }
}

public extension View {
    /// Presents the signing experience full screen while `isPresented` is `true`.
    ///
    /// `onResult` is called once, after the view has been dismissed. If the signer closes the view, or your
    /// code sets `isPresented` to `false` first, the result is `.canceled`.
    ///
    /// ```swift
    /// .wthaiqSigning(isPresented: $isSigning, url: signingURL) { result in
    ///     if result.isSigned { refreshOrder() }
    /// }
    /// ```
    func wthaiqSigning(
        isPresented: Binding<Bool>,
        url: URL?,
        configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration(),
        onEvent: ((SigningEvent) -> Void)? = nil,
        onResult: @escaping (SigningResult) -> Void
    ) -> some View {
        modifier(
            WthaiqSigningPresentationModifier(
                isPresented: isPresented,
                url: url,
                configuration: configuration,
                onEvent: onEvent,
                onResult: onResult
            )
        )
    }
}

struct WthaiqSigningPresentationModifier: ViewModifier {
    @Binding private var isPresented: Bool
    private let url: URL?
    private let configuration: WthaiqSigningConfiguration
    private let onEvent: ((SigningEvent) -> Void)?
    private let onResult: (SigningResult) -> Void
    @State private var pendingResult: SigningResult?

    init(
        isPresented: Binding<Bool>,
        url: URL?,
        configuration: WthaiqSigningConfiguration,
        onEvent: ((SigningEvent) -> Void)?,
        onResult: @escaping (SigningResult) -> Void
    ) {
        self._isPresented = isPresented
        self.url = url
        self.configuration = configuration
        self.onEvent = onEvent
        self.onResult = onResult
    }

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: deliverResult) {
            WthaiqSigningSheet(
                url: url,
                configuration: configuration,
                onEvent: onEvent,
                onDismissRequest: { isPresented = false },
                onResult: { result in pendingResult = result }
            )
        }
    }

    private func deliverResult() {
        let result = pendingResult ?? .canceled
        pendingResult = nil
        onResult(result)
    }
}

/// Bridges `WthaiqSigningViewController` into SwiftUI.
struct SigningControllerRepresentable: UIViewControllerRepresentable {
    let url: URL?
    let configuration: WthaiqSigningConfiguration
    let onEvent: ((SigningEvent) -> Void)?
    let onResult: (SigningResult) -> Void
    let onDismissRequest: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> WthaiqSigningViewController {
        let controller = WthaiqSigningViewController(optionalURL: url, configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: WthaiqSigningViewController, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleUIViewController(_ controller: WthaiqSigningViewController, coordinator: Coordinator) {
        controller.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, WthaiqSigningViewControllerDelegate {
        var parent: SigningControllerRepresentable

        init(parent: SigningControllerRepresentable) {
            self.parent = parent
        }

        func signingViewController(_ controller: WthaiqSigningViewController, didFinishWith result: SigningResult) {
            parent.onResult(result)
        }

        func signingViewController(_ controller: WthaiqSigningViewController, didReceive event: SigningEvent) {
            parent.onEvent?(event)
        }

        func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController) {
            parent.onDismissRequest()
        }
    }
}
#endif
