import Foundation

/// Drives the passkey-equivalent handshake with the backend: register the device
/// public key, then challenge → sign → verify to obtain a session token. No
/// shared secret is ever sent; the server only stores the public key.
struct AuthClient {
    let baseURL: URL

    /// Idempotent: binds this device's public key to the vault.
    func register(credentialID: String, publicKeyX963: String, vault: String) async {
        var req = post("auth/register")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "credential_id": credentialID, "public_key": publicKeyX963, "vault": vault,
        ])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// challenge → sign(challenge bytes) → verify → session token.
    func login(credentialID: String, sign: (Data) -> Data?) async -> String? {
        guard
            let (cData, _) = try? await URLSession.shared.data(for: post("auth/challenge")),
            let challenge = json(cData)?["challenge"] as? String,
            let challengeBytes = Data(base64Encoded: challenge),
            let signature = sign(challengeBytes)
        else { return nil }

        var verify = post("auth/verify")
        verify.httpBody = try? JSONSerialization.data(withJSONObject: [
            "credential_id": credentialID, "challenge": challenge, "signature": signature.base64EncodedString(),
        ])
        guard
            let (vData, resp) = try? await URLSession.shared.data(for: verify),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let token = json(vData)?["token"] as? String
        else { return nil }
        return token
    }

    private func post(_ path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Short timeout so a wrong dev server IP fails fast (the connection-state
        // button can report "hors ligne" in seconds, not after the 60s default).
        req.timeoutInterval = 8
        return req
    }

    private func json(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
