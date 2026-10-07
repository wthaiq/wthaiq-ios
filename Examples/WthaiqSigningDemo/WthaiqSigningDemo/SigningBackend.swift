import Foundation

/// Talks to your own backend, never to the Wthaiq API: the API key stays on your server.
///
/// The backend endpoint used here is a placeholder. On your server, create the signing link with a Wthaiq
/// server library and return it, for example (Node.js):
///
///     const session = await wt.signers.createSigningSession(signerId, { mode: 'iframe' });
///     res.json({ url: session.signing_url });
///
/// or return the `sign_url` of a session created with `POST /sessions`.
struct SigningBackend {
    /// Replace with your backend's base URL.
    static let placeholderBaseURL = "https://your-backend.example.com"

    enum BackendError: LocalizedError {
        case invalidBaseURL
        case badStatus(Int)
        case invalidSigningURL

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "Enter your backend URL first."
            case .badStatus(let status):
                return "Your backend answered with HTTP \(status)."
            case .invalidSigningURL:
                return "Your backend did not return a signing URL."
            }
        }
    }

    private struct SigningURLResponse: Decodable {
        let url: String
    }

    let baseURL: String

    /// `POST <backend>/wthaiq/signing-url` with `{"signer_id": "sgr_…"}` returns
    /// `{"url": "https://wthaiq.com/embed/sign/…"}`.
    func signingURL(forSigner signerID: String) async throws -> URL {
        guard let base = URL(string: baseURL), base.scheme == "https" else {
            throw BackendError.invalidBaseURL
        }
        var request = URLRequest(url: base.appendingPathComponent("wthaiq/signing-url"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["signer_id": signerID])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BackendError.badStatus(status)
        }
        let decoded = try JSONDecoder().decode(SigningURLResponse.self, from: data)
        guard let url = URL(string: decoded.url) else {
            throw BackendError.invalidSigningURL
        }
        return url
    }
}
