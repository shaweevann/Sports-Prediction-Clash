import Foundation
import Security

/// Talks to the game server. Creates an account the first time and keeps its token in the Keychain.
struct ClashAPI {
    /// The simulator reaches a server on this Mac at 127.0.0.1. Override with the "serverURL" default.
    var base = URL(string: UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:8787")!

    struct Failure: Error, LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    func feed() async throws -> FeedReply { try await call("GET", "/v1/feed") }

    func snap(_ req: SnapRequest) async throws -> SnapReply { try await call("POST", "/v1/snap", req) }

    func claim(_ req: ClaimRequest) async throws -> BalanceReply { try await call("POST", "/v1/missions/claim", req) }

    // MARK: Plumbing

    private func call<T: Decodable>(_ method: String, _ path: String, _ body: (some Encodable)? = Optional<Int>.none) async throws -> T {
        let token = try await account()
        do {
            return try await send(method, path, body, token: token)
        } catch let f as Failure where f.status == 401 {
            // The server no longer knows this token (say, its database was reset): start a fresh account once
            Keychain.delete()
            return try await send(method, path, body, token: try await account())
        }
    }

    private func account() async throws -> String {
        if let t = Keychain.read() { return t }
        let reply: AccountReply = try await send("POST", "/v1/accounts", AccountRequest(name: nil), token: nil)
        Keychain.save(reply.token)
        return reply.token
    }

    private func send<T: Decodable>(_ method: String, _ path: String, _ body: (some Encodable)?, token: String?) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, res) = try await URLSession.shared.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorReply.self, from: data))?.error ?? "The server answered \(status)."
            throw Failure(status: status, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// The account token, kept in the Keychain rather than in plain app storage.
enum Keychain {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "SportsPredictionClash",
                                               kSecAttrAccount as String: "token"]

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() { SecItemDelete(query as CFDictionary) }
}
