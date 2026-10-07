import Foundation

/// Maps WebKit and URL loading errors to `WthaiqSigningError`.
enum LoadFailure {
    /// Returns `nil` for errors that are not failures (a navigation that was canceled or replaced).
    static func classify(_ error: Error) -> WthaiqSigningError? {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled:
                return nil
            case NSURLErrorTimedOut:
                return .timedOut
            default:
                return .network(code: nsError.code, message: nsError.localizedDescription)
            }
        }
        if nsError.domain == "WebKitErrorDomain" {
            // 102: frame load interrupted by a policy decision; 204: load handled by a plug-in.
            if nsError.code == 102 || nsError.code == 204 {
                return nil
            }
        }
        return .network(code: nsError.code, message: nsError.localizedDescription)
    }

    /// The URL that failed, when the error carries it.
    static func failingURL(of error: Error) -> URL? {
        let nsError = error as NSError
        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let text = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return URL(string: text)
        }
        return nil
    }

    /// HTTP statuses that replace the page with the retry screen. Other 4xx pages are shown as served.
    static func isBlockingStatus(_ status: Int) -> Bool {
        status == 429 || status >= 500
    }
}
