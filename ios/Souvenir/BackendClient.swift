import Foundation
import CryptoKit

/// Talks to the dumb backend (ARCHITECTURE.md §1): uploads opaque encrypted
/// blobs + opaque metadata (a wrapped key + a blob hash). The server never sees
/// plaintext and never holds the vault key. Push is best-effort and idempotent
/// (content-addressed blobs + client-UUID entries), so retries are safe and the
/// app stays fully usable offline (ARCHITECTURE.md §2).
struct BackendClient {
    let baseURL: URL
    let token: String
    let vault: String

    /// Full commit sequence for one entry: upload blob → write metadata →
    /// re-fetch and verify the blob is byte-identical → commit. The self-check
    /// mirrors the on-device re-decryption check (SECURITY.md §1.6): never mark
    /// committed until we've confirmed the stored bytes are intact.
    func upload(entryID: String, wrappedKeyB64: String, blob: Data) async -> Bool {
        let hash = SHA256.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        do {
            try await putBlob(hash: hash, blob: blob)
            try await createEntry(entryID: entryID, wrappedKey: wrappedKeyB64, blobHash: hash)
            guard try await fetchBlob(hash: hash) == blob else { return false }
            try await commit(entryID: entryID)
            return true
        } catch {
            return false
        }
    }

    /// One opaque metadata row from a delta sync.
    struct Row {
        let entryID: String
        let committed: Bool
        let wrappedKey: String
        let blobHash: String
        let seq: Int
    }

    /// Delta pull of opaque rows for this vault (ARCHITECTURE.md §6 hot query).
    func fetchDelta(since: Int) async -> [Row] {
        do {
            let url = baseURL.appending(path: "vaults/\(vault)/entries")
                .appending(queryItems: [URLQueryItem(name: "since", value: String(since))])
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            try ensureOK(resp)
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let arr = obj?["entries"] as? [[String: Any]] ?? []
            return arr.map {
                Row(entryID: $0["entry_id"] as? String ?? "",
                    committed: $0["committed"] as? Bool ?? false,
                    wrappedKey: $0["wrapped_key"] as? String ?? "",
                    blobHash: $0["blob_hash"] as? String ?? "",
                    seq: $0["seq"] as? Int ?? 0)
            }
        } catch {
            return []
        }
    }

    /// Fetch an opaque blob (best-effort).
    func blob(hash: String) async -> Data? {
        try? await fetchBlob(hash: hash)
    }

    // MARK: routes

    private func putBlob(hash: String, blob: Data) async throws {
        var req = request("blobs/\(hash)", "PUT")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["data_b64": blob.base64EncodedString()])
        try await send(req)
    }

    private func createEntry(entryID: String, wrappedKey: String, blobHash: String) async throws {
        var req = request("vaults/\(vault)/entries", "POST")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "entry_id": entryID, "wrapped_key": wrappedKey, "blob_hash": blobHash,
        ])
        try await send(req)
    }

    private func commit(entryID: String) async throws {
        try await send(request("vaults/\(vault)/entries/\(entryID)/commit", "POST"))
    }

    private func fetchBlob(hash: String) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: request("blobs/\(hash)", "GET"))
        try ensureOK(resp)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Data(base64Encoded: obj?["data_b64"] as? String ?? "") ?? Data()
    }

    // MARK: helpers

    private func request(_ path: String, _ method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        try ensureOK(resp)
        return data
    }

    private func ensureOK(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
