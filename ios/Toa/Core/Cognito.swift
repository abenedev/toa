import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CognitoTokens {
    var idToken: String
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

enum AuthError: LocalizedError {
    case notConfigured
    case network
    case invalidResponse
    case cognito(code: String, message: String)

    var code: String? {
        if case .cognito(let code, _) = self { return code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Accounts aren't available in this build."
        case .network: "No internet connection. Try again once you're online."
        case .invalidResponse: "Unexpected response from the server."
        case .cognito(let code, let message):
            switch code {
            case "NotAuthorizedException": message.contains("password") ? "Incorrect email or password." : message
            case "UserNotFoundException": "Incorrect email or password."
            case "UsernameExistsException": "An account with this email already exists."
            case "CodeMismatchException": "Invalid verification code."
            case "ExpiredCodeException": "This code has expired. Request a new one."
            case "LimitExceededException", "TooManyRequestsException": "Too many attempts. Try again later."
            default: message
            }
        }
    }
}

/// Minimal client for the Cognito user pools API (no SDK, see
/// https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/).
/// The app client must have no secret and allow USER_PASSWORD_AUTH + REFRESH_TOKEN_AUTH.
struct CognitoClient {
    let region: String
    let clientId: String

    func signIn(email: String, password: String) async throws -> CognitoTokens {
        let response = try await call("InitiateAuth", [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": clientId,
            "AuthParameters": ["USERNAME": email, "PASSWORD": password],
        ])
        return try tokens(from: response, refreshToken: nil)
    }

    func refresh(refreshToken: String) async throws -> CognitoTokens {
        let response = try await call("InitiateAuth", [
            "AuthFlow": "REFRESH_TOKEN_AUTH",
            "ClientId": clientId,
            "AuthParameters": ["REFRESH_TOKEN": refreshToken],
        ])
        return try tokens(from: response, refreshToken: refreshToken)
    }

    /// Returns true when the account still needs its email confirmation code.
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await call("SignUp", [
            "ClientId": clientId,
            "Username": email,
            "Password": password,
            "UserAttributes": [["Name": "email", "Value": email]],
        ])
        return (response["UserConfirmed"] as? Bool) != true
    }

    func confirmSignUp(email: String, code: String) async throws {
        _ = try await call("ConfirmSignUp", ["ClientId": clientId, "Username": email, "ConfirmationCode": code])
    }

    func resendConfirmationCode(email: String) async throws {
        _ = try await call("ResendConfirmationCode", ["ClientId": clientId, "Username": email])
    }

    func forgotPassword(email: String) async throws {
        _ = try await call("ForgotPassword", ["ClientId": clientId, "Username": email])
    }

    func confirmForgotPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await call("ConfirmForgotPassword", [
            "ClientId": clientId, "Username": email, "ConfirmationCode": code, "Password": newPassword,
        ])
    }

    func changePassword(accessToken: String, old: String, new: String) async throws {
        _ = try await call("ChangePassword", [
            "AccessToken": accessToken, "PreviousPassword": old, "ProposedPassword": new,
        ])
    }

    /// Cognito emails a verification code to the new address.
    func updateEmail(accessToken: String, email: String) async throws {
        _ = try await call("UpdateUserAttributes", [
            "AccessToken": accessToken, "UserAttributes": [["Name": "email", "Value": email]],
        ])
    }

    func verifyEmail(accessToken: String, code: String) async throws {
        _ = try await call("VerifyUserAttribute", [
            "AccessToken": accessToken, "AttributeName": "email", "Code": code,
        ])
    }

    func deleteUser(accessToken: String) async throws {
        _ = try await call("DeleteUser", ["AccessToken": accessToken])
    }

    private func tokens(from response: [String: Any], refreshToken: String?) throws -> CognitoTokens {
        guard let result = response["AuthenticationResult"] as? [String: Any],
              let idToken = result["IdToken"] as? String,
              let accessToken = result["AccessToken"] as? String
        else {
            if let challenge = response["ChallengeName"] as? String {
                throw AuthError.cognito(code: challenge, message: "This account requires an action that isn't supported yet (\(challenge)).")
            }
            throw AuthError.invalidResponse
        }
        let expiresIn = (result["ExpiresIn"] as? Double) ?? 3600
        return CognitoTokens(
            idToken: idToken,
            accessToken: accessToken,
            refreshToken: (result["RefreshToken"] as? String) ?? refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func call(_ action: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard !region.isEmpty, !clientId.isEmpty,
              let url = URL(string: "https://cognito-idp.\(region).amazonaws.com/")
        else { throw AuthError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(action)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.network
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let type = (json["__type"] as? String ?? "UnknownError").components(separatedBy: "#").last ?? ""
            let message = json["message"] as? String ?? json["Message"] as? String ?? "Something went wrong."
            throw AuthError.cognito(code: type, message: message)
        }
        return json
    }
}

enum JWT {
    /// Unverified claims, only used to read `sub`/`email` of our own ID token.
    static func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
