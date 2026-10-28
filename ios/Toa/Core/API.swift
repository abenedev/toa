import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Build-time configuration, injected into Info.plist by the build (see ios/project.yml).
enum AppConfig {
    static func value(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        // Unset build settings come through empty or as the literal "$(VAR)".
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespaces)
    }

    static var apiBaseURL: URL? {
        let raw = value("TOAAPIBaseURL")
        return raw.isEmpty ? nil : URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }

    static var cognitoRegion: String { value("TOACognitoRegion") }
    static var cognitoClientId: String { value("TOACognitoClientID") }

    static var subscriptionProductId: String {
        let id = value("TOASubscriptionProductID")
        return id.isEmpty ? "dev.abene.toa.removeads.monthly" : id
    }

    /// Accounts & cloud sync need both the API and Cognito; guest mode works without.
    static var accountsEnabled: Bool {
        apiBaseURL != nil && !cognitoRegion.isEmpty && !cognitoClientId.isEmpty
    }
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case offline
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud sync isn't available in this build."
        case .unauthorized: "Your session has expired. Log in again."
        case .offline: "No internet connection."
        case .http(let status): "Server error (\(status))."
        }
    }
}

/// Backend client. `token(forceRefresh)` returns a valid Cognito ID token.
struct APIClient {
    let baseURL: URL
    let token: (_ forceRefresh: Bool) async throws -> String

    func sync(_ body: SyncRequest) async throws -> SyncResponse {
        try await send("POST", "/sync", body: try WireJSON.encoder.encode(body))
    }

    func me() async throws -> ProfileDTO {
        try await send("GET", "/me")
    }

    func deleteMe() async throws {
        let _: Empty = try await send("DELETE", "/me")
    }

    func submitAppleTransaction(_ jws: String) async throws -> ProfileDTO {
        try await send("POST", "/billing/apple/transactions", body: try JSONSerialization.data(withJSONObject: ["signed_transaction": jws]))
    }

    private struct Empty: Decodable {}

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        var forceRefresh = false
        while true {
            var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())))
            request.httpMethod = method
            request.httpBody = body
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(try await token(forceRefresh))", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw APIError.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !forceRefresh {
                forceRefresh = true
                continue
            }
            if status == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(status) else { throw APIError.http(status) }
            if T.self == Empty.self { return Empty() as! T }
            return try WireJSON.decoder.decode(T.self, from: data)
        }
    }
}
