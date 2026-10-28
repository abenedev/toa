import Foundation
import Observation
import Security

enum Keychain {
    private static let service = "dev.abene.toa"

    static func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Who is using the app. Guests keep everything on the device; signed-in users
/// also get cloud sync. Being offline never signs anyone out.
@MainActor
@Observable
final class Session {
    enum State: String {
        case signedOut, guest, signedIn
    }

    private(set) var state: State
    private(set) var email: String?
    /// Cognito `sub`; also the StoreKit appAccountToken.
    private(set) var userId: String?
    /// The refresh token was rejected: sync is paused until the user logs in again.
    private(set) var needsReauth = false

    private var tokens: CognitoTokens?
    private let defaults = UserDefaults.standard

    /// Called when local data must be erased (account switch, sign out).
    var onWipe: () -> Void = {}
    /// Called after a successful login so the app syncs right away.
    var onSignedIn: () -> Void = {}

    init() {
        state = State(rawValue: defaults.string(forKey: "session.state") ?? "") ?? .signedOut
        email = defaults.string(forKey: "session.email")
        userId = defaults.string(forKey: "session.userId")
        if state == .signedIn, Keychain.get("refreshToken") == nil { state = .signedOut }
    }

    var cognito: CognitoClient {
        CognitoClient(region: AppConfig.cognitoRegion, clientId: AppConfig.cognitoClientId)
    }

    var isSignedIn: Bool { state == .signedIn }

    func continueAsGuest() {
        set(state: .guest)
    }

    func signIn(email rawEmail: String, password: String) async throws {
        let email = rawEmail.trimmingCharacters(in: .whitespaces).lowercased()
        let tokens = try await cognito.signIn(email: email, password: password)
        let claims = JWT.claims(tokens.idToken)
        guard let sub = claims["sub"] as? String else { throw AuthError.invalidResponse }

        // Guest data is merged into the account; another account's data is not.
        let previousOwner = defaults.string(forKey: "session.owner")
        if let previousOwner, previousOwner != sub {
            onWipe()
        }
        defaults.set(sub, forKey: "session.owner")

        self.tokens = tokens
        Keychain.set(tokens.refreshToken, for: "refreshToken")
        userId = sub
        self.email = (claims["email"] as? String) ?? email
        defaults.set(userId, forKey: "session.userId")
        defaults.set(self.email, forKey: "session.email")
        needsReauth = false
        set(state: .signedIn)
        onSignedIn()
    }

    /// Ends the session and erases local data (the caller confirms first).
    func signOut() {
        onWipe()
        tokens = nil
        Keychain.set(nil, for: "refreshToken")
        defaults.removeObject(forKey: "session.owner")
        defaults.removeObject(forKey: "session.email")
        defaults.removeObject(forKey: "session.userId")
        email = nil
        userId = nil
        needsReauth = false
        set(state: .signedOut)
    }

    /// A valid ID token for the backend, refreshed when needed.
    func idToken(forceRefresh: Bool = false) async throws -> String {
        try await validTokens(forceRefresh: forceRefresh).idToken
    }

    func accessToken() async throws -> String {
        try await validTokens(forceRefresh: false).accessToken
    }

    /// Picks up a new email after it was verified.
    func refreshProfile() async {
        guard let tokens = try? await validTokens(forceRefresh: true) else { return }
        if let email = JWT.claims(tokens.idToken)["email"] as? String {
            self.email = email
            defaults.set(email, forKey: "session.email")
        }
    }

    private func validTokens(forceRefresh: Bool) async throws -> CognitoTokens {
        guard state == .signedIn else { throw APIError.unauthorized }
        if !forceRefresh, let tokens, tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens
        }
        guard let refreshToken = Keychain.get("refreshToken") else {
            needsReauth = true
            throw APIError.unauthorized
        }
        do {
            let refreshed = try await cognito.refresh(refreshToken: refreshToken)
            tokens = refreshed
            needsReauth = false
            return refreshed
        } catch let error as AuthError {
            if case .cognito(let code, _) = error, code == "NotAuthorizedException" {
                needsReauth = true
                throw APIError.unauthorized
            }
            throw APIError.offline
        }
    }

    private func set(state: State) {
        self.state = state
        defaults.set(state.rawValue, forKey: "session.state")
    }
}
