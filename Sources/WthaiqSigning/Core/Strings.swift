import Foundation

/// Text shown by the SDK itself, in formal Arabic and English. Kept in code (not in a resource bundle) so
/// every string is covered by unit tests.
struct SigningStrings: Hashable, Sendable {
    let language: ResolvedLanguage
    let title: String
    let close: String
    let loading: String
    let retry: String
    let confirmTitle: String
    let confirmMessage: String
    let confirmLeave: String
    let confirmStay: String
    let announceSigned: String
    let announceDeclined: String
    let okay: String
    let cancel: String
    let offlineTitle: String
    let offlineMessage: String
    let timeoutTitle: String
    let timeoutMessage: String
    let serverTitle: String
    let serverMessage: String
    let genericTitle: String
    let genericMessage: String
    let invalidLinkTitle: String
    let invalidLinkMessage: String
    let crashTitle: String
    let crashMessage: String

    var isRightToLeft: Bool { language.isRightToLeft }

    static func make(_ language: ResolvedLanguage) -> SigningStrings {
        switch language {
        case .arabic:
            return SigningStrings(
                language: .arabic,
                title: "توقيع المستند",
                close: "إغلاق",
                loading: "جارٍ تحميل المستند…",
                retry: "إعادة المحاولة",
                confirmTitle: "الخروج من التوقيع؟",
                confirmMessage: "لم يكتمل التوقيع بعد، ويمكنك فتح الرابط مرّة أخرى لاحقًا لإتمامه.",
                confirmLeave: "خروج",
                confirmStay: "متابعة التوقيع",
                announceSigned: "تمّ توقيع المستند.",
                announceDeclined: "سُجِّل اعتذارك عن التوقيع.",
                okay: "حسنًا",
                cancel: "إلغاء",
                offlineTitle: "لا يوجد اتصال بالإنترنت",
                offlineMessage: "تحقّق من اتصالك بالإنترنت، ثم أعد المحاولة.",
                timeoutTitle: "استغرق التحميل وقتًا أطول من المعتاد",
                timeoutMessage: "الاتصال بطيء أو متقطّع. أعد المحاولة بعد لحظات.",
                serverTitle: "الخدمة غير متاحة مؤقّتًا",
                serverMessage: "تعذّر الوصول إلى صفحة التوقيع الآن. أعد المحاولة بعد لحظات.",
                genericTitle: "تعذّر تحميل المستند",
                genericMessage: "حدث خطأ أثناء تحميل صفحة التوقيع. أعد المحاولة.",
                invalidLinkTitle: "لا يمكن فتح رابط التوقيع",
                invalidLinkMessage: "هذا الرابط غير صالح للتوقيع داخل التطبيق. اطلب من مُرسِل المستند رابطًا جديدًا.",
                crashTitle: "توقّفت الصفحة على نحو غير متوقّع",
                crashMessage: "أعد تحميل الصفحة لمتابعة التوقيع."
            )
        case .english:
            return SigningStrings(
                language: .english,
                title: "Sign document",
                close: "Close",
                loading: "Loading the document…",
                retry: "Try again",
                confirmTitle: "Leave signing?",
                confirmMessage: "The document has not been signed yet. You can open the link again later to finish.",
                confirmLeave: "Leave",
                confirmStay: "Continue signing",
                announceSigned: "The document has been signed.",
                announceDeclined: "You declined to sign.",
                okay: "OK",
                cancel: "Cancel",
                offlineTitle: "No internet connection",
                offlineMessage: "Check your connection, then try again.",
                timeoutTitle: "This is taking longer than usual",
                timeoutMessage: "The connection is slow or interrupted. Try again in a moment.",
                serverTitle: "Service temporarily unavailable",
                serverMessage: "The signing page cannot be reached right now. Try again in a moment.",
                genericTitle: "The document could not be loaded",
                genericMessage: "Something went wrong while loading the signing page. Try again.",
                invalidLinkTitle: "This signing link cannot be opened",
                invalidLinkMessage: "This link cannot be used for signing in the app. Ask the sender for a new link.",
                crashTitle: "The page stopped unexpectedly",
                crashMessage: "Reload the page to continue signing."
            )
        }
    }

    /// Title and message for the error screen.
    func errorText(for error: WthaiqSigningError) -> (title: String, message: String) {
        if error.isOffline {
            return (offlineTitle, offlineMessage)
        }
        switch error {
        case .timedOut:
            return (timeoutTitle, timeoutMessage)
        case .httpStatus:
            return (serverTitle, serverMessage)
        case .invalidURL, .linkUnavailable, .unexpectedReturnStatus:
            return (invalidLinkTitle, invalidLinkMessage)
        case .webContentTerminated:
            return (crashTitle, crashMessage)
        case .network, .pageError:
            return (genericTitle, genericMessage)
        }
    }

    /// SF Symbol for the error screen.
    static func symbolName(for error: WthaiqSigningError) -> String {
        if error.isOffline {
            return "wifi.exclamationmark"
        }
        switch error {
        case .timedOut:
            return "clock.badge.exclamationmark"
        case .invalidURL, .linkUnavailable, .unexpectedReturnStatus:
            return "link"
        case .network, .httpStatus, .pageError, .webContentTerminated:
            return "exclamationmark.triangle"
        }
    }
}
