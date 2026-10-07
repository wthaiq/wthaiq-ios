#if os(iOS)
import UIKit
import WebKit

/// Receives the result, events and dismissal requests of a `WthaiqSigningViewController`.
/// Every method except `didFinishWith` has a default implementation.
@MainActor
public protocol WthaiqSigningViewControllerDelegate: AnyObject {
    /// The session ended. Called exactly once.
    func signingViewController(_ controller: WthaiqSigningViewController, didFinishWith result: SigningResult)

    /// An informational event (page loaded, identity verification started, link opened in Safari…).
    func signingViewController(_ controller: WthaiqSigningViewController, didReceive event: SigningEvent)

    /// The signer tapped Close, or the automatic dismissal delay elapsed after a result. The default
    /// implementation calls `controller.dismissFromContainer()`.
    func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController)

    /// Return `false` to handle an external link yourself. The default opens it with `UIApplication.open`.
    func signingViewController(_ controller: WthaiqSigningViewController, shouldOpenExternalURL url: URL) -> Bool
}

@MainActor
public extension WthaiqSigningViewControllerDelegate {
    func signingViewController(_ controller: WthaiqSigningViewController, didReceive event: SigningEvent) {}

    func signingViewControllerDidRequestDismissal(_ controller: WthaiqSigningViewController) {
        controller.dismissFromContainer()
    }

    func signingViewController(_ controller: WthaiqSigningViewController, shouldOpenExternalURL url: URL) -> Bool {
        true
    }
}

/// Shows a Wthaiq signing page natively and reports how the session ended.
///
/// Give it a URL your backend obtained from the Wthaiq API — a signer's `signing_url`, a session's `sign_url`,
/// or the `signing_url` of `POST /signers/{id}/signing_session`. Never put an API key in the app.
///
/// ```swift
/// let controller = WthaiqSigningViewController(url: signingURL)
/// controller.delegate = self
/// present(controller, animated: true)
/// ```
@MainActor
public final class WthaiqSigningViewController: UIViewController {

    /// Receives the result and events.
    public weak var delegate: WthaiqSigningViewControllerDelegate?

    /// The URL given at creation.
    public let url: URL?

    /// The configuration given at creation.
    public let configuration: WthaiqSigningConfiguration

    /// The result, once the session has ended.
    public private(set) var finalResult: SigningResult?

    /// Called once when the controller leaves its container (dismissed or popped).
    var didLeaveHandler: (() -> Void)?

    private let language: ResolvedLanguage
    private let strings: SigningStrings
    private var policy: NavigationPolicy
    private var flow = SigningFlow()
    private var link: SigningLink?
    private var webView: WKWebView?

    private let contentGuide = UILayoutGuide()
    private let headerBackground = UIView()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let headerView: SigningHeaderView
    private let statusView: SigningStatusView

    private var timeoutTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var continuations: [CheckedContinuation<SigningResult, Never>] = []

    private var hasFinishedFirstLoad = false
    private var isMainFrameLoading = false
    private var visibleError: WthaiqSigningError?
    private var retryURL: URL?
    private var terminationCount = 0
    private var hasLeft = false

    /// Creates the controller. The URL is validated against `configuration` when the view loads; an invalid
    /// URL shows an error screen and finishes with `.failed(.invalidURL(…))`.
    public convenience init(url: URL, configuration: WthaiqSigningConfiguration = WthaiqSigningConfiguration()) {
        self.init(optionalURL: url, configuration: configuration)
    }

    init(optionalURL: URL?, configuration: WthaiqSigningConfiguration) {
        self.url = optionalURL
        self.configuration = configuration
        let language = ResolvedLanguage.resolve(
            configuration.language,
            preferredLanguages: ResolvedLanguage.appPreferredLanguages()
        )
        let strings = SigningStrings.make(language)
        self.language = language
        self.strings = strings
        self.policy = NavigationPolicy(configuration: configuration)
        self.headerView = SigningHeaderView(
            title: configuration.appearance.title ?? strings.title,
            closeLabel: strings.close,
            showsCloseButton: configuration.showsCloseButton
        )
        self.statusView = SigningStatusView(tint: configuration.appearance.tintColor)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - Public API

    /// Waits for the session to end and returns its result (immediately if it has already ended).
    public func result() async -> SigningResult {
        if let finalResult {
            return finalResult
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// Ends the session with `.canceled` (if it has not ended yet) and stops loading. Does not dismiss.
    public func cancel() {
        timeoutTask?.cancel()
        webView?.stopLoading()
        apply(flow.cancel(showingError: nil))
    }

    /// Reloads the signing page (or retries the page that failed).
    public func reload() {
        retry()
    }

    /// Dismisses the controller if it was presented, or pops it if it was pushed.
    public func dismissFromContainer(animated: Bool = true) {
        if let navigation = navigationController,
           navigation.topViewController === self,
           navigation.viewControllers.first !== self {
            _ = navigation.popViewController(animated: animated)
            return
        }
        if presentingViewController != nil {
            dismiss(animated: animated)
        }
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.tintColor = configuration.appearance.tintColor.uiColor
        view.accessibilityLanguage = language.rawValue
        overrideUserInterfaceStyle = configuration.appearance.interfaceStyle.userInterfaceStyle

        layoutChrome()
        applyLayoutDirection()

        switch SigningLink.check(url, configuration: configuration) {
        case .success(let link):
            self.link = link
            installWebView()
            load(link.url(for: configuration.language))
        case .failure(let reason):
            let error = WthaiqSigningError.invalidURL(reason)
            showError(error)
            apply(flow.fail(error))
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let container = presentationContainer,
           let presentation = container.presentationController,
           presentation.delegate == nil {
            presentation.delegate = self
            container.isModalInPresentation = true
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isLeavingContainer, !hasLeft else { return }
        hasLeft = true
        timeoutTask?.cancel()
        dismissTask?.cancel()
        webView?.stopLoading()
        apply(flow.cancel(showingError: nil))
        didLeaveHandler?()
    }

    // MARK: - Layout

    private var presentationContainer: UIViewController? {
        if parent == nil, presentingViewController != nil {
            return self
        }
        if let navigation = navigationController,
           navigation.parent == nil,
           navigation.viewControllers.first === self,
           navigation.presentingViewController != nil {
            return navigation
        }
        return nil
    }

    private var isLeavingContainer: Bool {
        var current: UIViewController? = self
        while let controller = current {
            if controller.isBeingDismissed || controller.isMovingFromParent {
                return true
            }
            current = controller.parent
        }
        return false
    }

    private func layoutChrome() {
        view.addLayoutGuide(contentGuide)
        let safeArea = view.safeAreaLayoutGuide
        var contentTop = safeArea.topAnchor

        if configuration.appearance.showsHeader {
            if let navigation = navigationController {
                navigationItem.title = configuration.appearance.title ?? strings.title
                if configuration.showsCloseButton {
                    let item = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
                    item.accessibilityLabel = strings.close
                    if navigation.viewControllers.first === self {
                        navigationItem.leftBarButtonItem = item
                    } else {
                        navigationItem.rightBarButtonItem = item
                    }
                }
            } else {
                headerBackground.backgroundColor = .systemBackground
                headerBackground.translatesAutoresizingMaskIntoConstraints = false
                headerView.translatesAutoresizingMaskIntoConstraints = false
                headerView.closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
                view.addSubview(headerBackground)
                view.addSubview(headerView)
                NSLayoutConstraint.activate([
                    headerBackground.topAnchor.constraint(equalTo: view.topAnchor),
                    headerBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    headerBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    headerBackground.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
                    headerView.topAnchor.constraint(equalTo: safeArea.topAnchor),
                    headerView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
                    headerView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
                ])
                contentTop = headerView.bottomAnchor
            }
        }

        NSLayoutConstraint.activate([
            contentGuide.topAnchor.constraint(equalTo: contentTop),
            contentGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        statusView.translatesAutoresizingMaskIntoConstraints = false
        statusView.onRetry = { [weak self] in self?.retry() }
        statusView.onClose = { [weak self] in self?.closeTapped() }
        view.addSubview(statusView)
        pin(statusView, to: contentGuide)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = configuration.appearance.tintColor.uiColor
        progressView.trackTintColor = .clear
        progressView.alpha = 0
        progressView.isAccessibilityElement = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    /// `semanticContentAttribute` is not inherited, so it is set on every view of the SDK's chrome.
    /// The web view is added later and keeps the page's own direction.
    private func applyLayoutDirection() {
        let attribute: UISemanticContentAttribute = language.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        func setDirection(of target: UIView) {
            target.semanticContentAttribute = attribute
            for child in target.subviews {
                setDirection(of: child)
            }
        }
        setDirection(of: view)
    }

    private func pin(_ subview: UIView, to guide: UILayoutGuide) {
        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: guide.topAnchor),
            subview.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
    }

    // MARK: - Web view

    private func installWebView() {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = configuration.usesEphemeralWebsiteData
            ? WKWebsiteDataStore.nonPersistent()
            : WKWebsiteDataStore.default()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.dataDetectorTypes = []
        webConfiguration.applicationNameForUserAgent = "Mobile/15E148 WthaiqSigning-iOS/\(WthaiqSigningSDK.version)"
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let world = WKContentWorld.world(name: BridgeScript.contentWorldName)
        let contentController = WKUserContentController()
        let usage = UsageDescriptions.read()
        let script = WKUserScript(
            source: BridgeScript.source(stripsCaptureAttribute: !usage.camera),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        )
        contentController.addUserScript(script)
        contentController.add(ScriptMessageProxy(owner: self), contentWorld: world, name: BridgeScript.handlerName)
        webConfiguration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.alpha = 0
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = configuration.isInspectable
        }

        view.insertSubview(webView, at: 0)
        pin(webView, to: contentGuide)
        self.webView = webView
    }

    private func load(_ target: URL) {
        hideError()
        retryURL = target
        if !hasFinishedFirstLoad || !statusView.isHidden {
            statusView.showLoading(text: strings.loading)
            statusView.isHidden = false
        }
        let request = URLRequest(
            url: target,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: configuration.effectiveTimeout
        )
        _ = webView?.load(request)
    }

    private func retry() {
        guard let link else { return }
        terminationCount = 0
        load(retryURL ?? link.url(for: configuration.language))
    }

    /// Shows load progress in three steps (started, committed, finished) from the navigation callbacks.
    private func updateProgress(_ value: Float) {
        guard configuration.appearance.showsProgressBar else { return }
        let progress = min(max(value, 0), 1)
        progressView.setProgress(progress, animated: progress > progressView.progress)
        let targetAlpha: CGFloat = progress < 1 ? 1 : 0
        let delay: TimeInterval = progress < 1 ? 0 : 0.2
        UIView.animate(withDuration: 0.25, delay: delay, options: [.beginFromCurrentState]) {
            self.progressView.alpha = targetAlpha
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        let nanoseconds = UInt64(configuration.effectiveTimeout * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.handleTimeout()
        }
    }

    private func handleTimeout() {
        guard isMainFrameLoading, finalResult == nil else { return }
        webView?.stopLoading()
        showLoadError(.timedOut, failingURL: nil)
    }

    private func revealContent() {
        guard visibleError == nil else { return }
        statusView.isHidden = true
        guard let webView, webView.alpha < 1 else { return }
        if hasFinishedFirstLoad {
            webView.alpha = 1
        } else {
            UIView.animate(withDuration: 0.2) {
                webView.alpha = 1
            }
        }
    }

    // MARK: - Errors

    private func showLoadError(_ error: WthaiqSigningError, failingURL: URL?) {
        timeoutTask?.cancel()
        isMainFrameLoading = false
        if let failingURL, ["http", "https"].contains(failingURL.scheme?.lowercased() ?? "") {
            retryURL = failingURL
        }
        showError(error)
        emit(.loadFailed(error))
    }

    private func showError(_ error: WthaiqSigningError) {
        visibleError = error
        let text = strings.errorText(for: error)
        statusView.showError(
            title: text.title,
            message: text.message,
            symbolName: SigningStrings.symbolName(for: error),
            retryTitle: (error.isRetryable && link != nil) ? strings.retry : nil,
            closeTitle: configuration.showsCloseButton ? strings.close : nil
        )
        statusView.isHidden = false
        UIAccessibility.post(notification: .screenChanged, argument: statusView.titleLabel)
    }

    private func hideError() {
        visibleError = nil
    }

    // MARK: - Session

    func receive(_ message: WKScriptMessage) {
        guard message.name == BridgeScript.handlerName else { return }
        let origin = message.frameInfo.securityOrigin
        guard policy.isPlatformFrame(scheme: origin.protocol, host: origin.host) else { return }
        let currentPolicy = policy
        let signal = PageMessageDecoder.decode(message.body) { currentPolicy.isPlatformOrigin($0) }
        guard let signal else { return }
        apply(flow.apply(signal))
    }

    private func apply(_ effect: SigningFlow.Effect) {
        switch effect {
        case .ignored:
            break
        case .event(let event):
            emit(event)
        case .finish(let result):
            finish(result)
        }
    }

    private func finish(_ result: SigningResult) {
        guard finalResult == nil else { return }
        finalResult = result
        policy.markFinished()
        timeoutTask?.cancel()
        announce(result)

        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: result)
        }
        delegate?.signingViewController(self, didFinishWith: result)
        scheduleAutomaticDismissal(for: result)
    }

    private func scheduleAutomaticDismissal(for result: SigningResult) {
        guard let delay = configuration.dismissalDelay else { return }
        switch result {
        case .signed, .declined:
            break
        case .canceled, .expired, .failed:
            return
        }
        dismissTask?.cancel()
        let nanoseconds = UInt64(delay * 1_000_000_000)
        dismissTask = Task { [weak self] in
            if nanoseconds > 0 {
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            self?.requestDismissal()
        }
    }

    private func requestDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
        if let delegate {
            delegate.signingViewControllerDidRequestDismissal(self)
        } else {
            dismissFromContainer()
        }
    }

    @objc private func closeTapped() {
        if finalResult != nil {
            requestDismissal()
            return
        }
        let shouldConfirm = configuration.appearance.confirmsBeforeClosing
            && hasFinishedFirstLoad
            && visibleError == nil
            && presentedViewController == nil
        if shouldConfirm {
            presentCloseConfirmation()
        } else {
            closeNow()
        }
    }

    private func closeNow() {
        timeoutTask?.cancel()
        webView?.stopLoading()
        apply(flow.cancel(showingError: visibleError))
        requestDismissal()
    }

    private func presentCloseConfirmation() {
        let alert = UIAlertController(title: strings.confirmTitle, message: strings.confirmMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.confirmStay, style: .cancel))
        alert.addAction(UIAlertAction(title: strings.confirmLeave, style: .destructive) { [weak self] _ in
            self?.closeNow()
        })
        present(alert, animated: true)
    }

    private func announce(_ result: SigningResult) {
        let text: String
        switch result {
        case .signed:
            text = strings.announceSigned
        case .declined:
            text = strings.announceDeclined
        case .canceled, .expired, .failed:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func emit(_ event: SigningEvent) {
        delegate?.signingViewController(self, didReceive: event)
    }

    // MARK: - Navigation

    /// Applies a navigation decision. Returns `true` when the navigation may proceed.
    private func handle(_ decision: NavigationDecision, url target: URL) -> Bool {
        switch decision {
        case .allow:
            return true
        case .allowExternalFlow(let host):
            emit(.identityVerificationStarted(host: host))
            return true
        case .cancel(let reason):
            if reason != .finished {
                emit(.navigationBlocked(target))
            }
            return false
        case .openExternally(let external):
            openExternally(external)
            return false
        case .complete(let match):
            apply(flow.apply(returnMatch: match))
            return false
        }
    }

    private func openExternally(_ target: URL) {
        let scheme = target.scheme?.lowercased() ?? ""
        guard ["https", "http", "mailto", "tel", "sms"].contains(scheme) else { return }
        if let delegate, !delegate.signingViewController(self, shouldOpenExternalURL: target) {
            return
        }
        UIApplication.shared.open(target, options: [:], completionHandler: nil)
        emit(.externalURLOpened(target))
    }

    private static func sourceHost(of action: WKNavigationAction) -> String? {
        // `sourceFrame` is declared non-optional but can be nil (for example for the first load);
        // reading it through key-value coding avoids a crash in that case.
        guard let frame = action.value(forKey: "sourceFrame") as? WKFrameInfo else { return nil }
        let host = frame.securityOrigin.host
        return host.isEmpty ? nil : host
    }

    private var canPresentPanel: Bool {
        viewIfLoaded?.window != nil && presentedViewController == nil
    }
}

// MARK: - WKNavigationDelegate

extension WthaiqSigningViewController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let target = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let request = NavigationRequest(
            url: target,
            isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            opensNewWindow: navigationAction.targetFrame == nil,
            trigger: NavigationTrigger(navigationAction.navigationType),
            sourceHost: WthaiqSigningViewController.sourceHost(of: navigationAction)
        )
        let decision = policy.decide(request)
        decisionHandler(handle(decision, url: target) ? .allow : .cancel)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           LoadFailure.isBlockingStatus(response.statusCode) {
            decisionHandler(.cancel)
            showLoadError(.httpStatus(response.statusCode), failingURL: response.url)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isMainFrameLoading = true
        updateProgress(0.1)
        startTimeout()
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateProgress(0.6)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isMainFrameLoading = false
        timeoutTask?.cancel()
        updateProgress(1)
        terminationCount = 0
        revealContent()
        hasFinishedFirstLoad = true
        if let current = webView.url {
            emit(.pageLoaded(current))
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        terminationCount += 1
        guard finalResult == nil else { return }
        if terminationCount <= 1, webView.url != nil {
            _ = webView.reload()
        } else {
            showLoadError(.webContentTerminated, failingURL: webView.url)
        }
    }

    private func handleNavigationError(_ error: Error) {
        isMainFrameLoading = false
        timeoutTask?.cancel()
        updateProgress(1)
        guard finalResult == nil, let failure = LoadFailure.classify(error) else { return }
        showLoadError(failure, failingURL: LoadFailure.failingURL(of: error))
    }
}

// MARK: - WKUIDelegate

extension WthaiqSigningViewController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let target = navigationAction.request.url {
            let request = NavigationRequest(
                url: target,
                isMainFrame: false,
                opensNewWindow: true,
                trigger: NavigationTrigger(navigationAction.navigationType),
                sourceHost: WthaiqSigningViewController.sourceHost(of: navigationAction)
            )
            _ = handle(policy.decide(request), url: target)
        }
        return nil
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let reply = PanelReply<Void>(fallback: ()) { _ in completionHandler() }
        guard canPresentPanel else {
            reply.send(())
            return
        }
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.okay, style: .default) { _ in reply.send(()) })
        present(alert, animated: true)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let reply = PanelReply<Bool>(fallback: false, handler: completionHandler)
        guard canPresentPanel else {
            reply.send(false)
            return
        }
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings.cancel, style: .cancel) { _ in reply.send(false) })
        alert.addAction(UIAlertAction(title: strings.okay, style: .default) { _ in reply.send(true) })
        present(alert, animated: true)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let reply = PanelReply<String?>(fallback: nil, handler: completionHandler)
        guard canPresentPanel else {
            reply.send(nil)
            return
        }
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
        }
        alert.addAction(UIAlertAction(title: strings.cancel, style: .cancel) { _ in reply.send(nil) })
        alert.addAction(UIAlertAction(title: strings.okay, style: .default) { [weak alert] _ in
            reply.send(alert?.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let kind: MediaCaptureKind
        switch type {
        case .camera:
            kind = .camera
        case .microphone:
            kind = .microphone
        case .cameraAndMicrophone:
            kind = .cameraAndMicrophone
        @unknown default:
            decisionHandler(.deny)
            return
        }
        let allowed = policy.allowsMediaCapture(
            kind,
            scheme: origin.protocol,
            host: origin.host,
            usage: UsageDescriptions.read()
        )
        decisionHandler(allowed ? .grant : .deny)
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension WthaiqSigningViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        closeTapped()
    }
}

// MARK: - Helpers

extension NavigationTrigger {
    init(_ type: WKNavigationType) {
        switch type {
        case .linkActivated:
            self = .linkActivated
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .other
        }
    }
}

/// Forwards bridge messages without retaining the controller (`WKUserContentController` keeps its handlers).
@MainActor
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var owner: WthaiqSigningViewController?

    init(owner: WthaiqSigningViewController) {
        self.owner = owner
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

/// Calls a WebKit panel completion handler exactly once, with a fallback if the alert goes away unanswered
/// (WebKit raises an exception when a panel completion handler is never called).
final class PanelReply<Value> {
    private var handler: ((Value) -> Void)?
    private let fallback: Value

    init(fallback: Value, handler: @escaping (Value) -> Void) {
        self.fallback = fallback
        self.handler = handler
    }

    func send(_ value: Value) {
        let pending = handler
        handler = nil
        pending?(value)
    }

    deinit {
        handler?(fallback)
    }
}
#endif
