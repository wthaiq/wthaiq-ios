import SwiftUI
import UIKit
import WthaiqSigning

struct ContentView: View {
    @State private var backendURL = SigningBackend.placeholderBaseURL
    @State private var signerID = "sgr_"
    @State private var pastedURL = ""
    @State private var language: WthaiqSigningConfiguration.Language = .automatic
    @State private var signingURL: URL?
    @State private var isSigning = false
    @State private var isLoading = false
    @State private var status = "No signing session yet."

    private var configuration: WthaiqSigningConfiguration {
        var configuration = WthaiqSigningConfiguration(language: language)
        // Your return URL (the `return_url` you passed to the API), if any. Navigation to it ends the session.
        if let returnURL = URL(string: "https://your-app.example.com/signing/done") {
            configuration.addReturnURL(returnURL)
        }
        // If your account signs on a custom domain, allow it:
        // configuration.addAllowedHost("sign.your-company.com")
        return configuration
    }

    var body: some View {
        NavigationView {
            Form {
                backendSection
                pasteSection
                Section("Language") {
                    Picker("Language", selection: $language) {
                        Text("Automatic").tag(WthaiqSigningConfiguration.Language.automatic)
                        Text("العربية").tag(WthaiqSigningConfiguration.Language.arabic)
                        Text("English").tag(WthaiqSigningConfiguration.Language.english)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Last result") {
                    Text(status)
                        .font(.callout)
                }
            }
            .navigationTitle("Wthaiq Signing")
        }
        .navigationViewStyle(.stack)
        .wthaiqSigning(isPresented: $isSigning, url: signingURL, configuration: configuration) { result in
            status = Self.describe(result)
        }
    }

    private var backendSection: some View {
        Section {
            TextField("Backend URL", text: $backendURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            TextField("Signer ID (sgr_…)", text: $signerID)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button {
                Task { await fetchAndSign() }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Get a signing link and sign")
                }
            }
            .disabled(isLoading)
        } header: {
            Text("1. From your backend")
        } footer: {
            Text("Your backend creates the signing link with its secret API key. The app never holds an API key.")
        }
    }

    private var pasteSection: some View {
        Section {
            TextField("https://wthaiq.com/embed/sign/…", text: $pastedURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Button("Open with SwiftUI") {
                open(pastedURL)
            }
            Button("Open with UIKit") {
                Task { await openWithUIKit(pastedURL) }
            }
        } header: {
            Text("2. Or paste a signing link")
        } footer: {
            Text("Embedded signing links from POST /signers/{id}/signing_session last 30 minutes.")
        }
    }

    @MainActor
    private func fetchAndSign() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let backend = SigningBackend(baseURL: backendURL)
            signingURL = try await backend.signingURL(forSigner: signerID)
            isSigning = true
        } catch {
            status = error.localizedDescription
        }
    }

    private func open(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = "That is not a valid URL."
            return
        }
        signingURL = url
        isSigning = true
    }

    @MainActor
    private func openWithUIKit(_ text: String) async {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            status = "That is not a valid URL."
            return
        }
        guard let presenter = Self.topViewController() else {
            status = "No window to present from."
            return
        }
        let result = await presenter.presentWthaiqSigning(url: url, configuration: configuration)
        status = Self.describe(result)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    /// In a real app, confirm the outcome on your backend (webhook or GET /signature_requests/{id})
    /// before treating the document as signed.
    private static func describe(_ result: SigningResult) -> String {
        switch result {
        case .signed(let outcome):
            let request = outcome.reference.signatureRequestID ?? "unknown request"
            if outcome.wasAlreadyFinal {
                return "Already signed (\(request))."
            }
            return "Signed (\(request)). Confirm it on your backend."
        case .declined(let outcome):
            return "Declined (\(outcome.reference.signatureRequestID ?? "unknown request"))."
        case .canceled:
            return "Closed before finishing."
        case .expired:
            return "The link has expired. Ask your backend for a new one."
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }
}
