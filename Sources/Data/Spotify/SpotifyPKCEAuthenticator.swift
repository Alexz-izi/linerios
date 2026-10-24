//
//  SpotifyPKCEAuthenticator.swift
//  LineriOS
//
//  RFC 7636 OAuth 2.0 PKCE authentication client using ASWebAuthenticationSession + CryptoKit.
//  Operates without client secrets or backend servers, persisting tokens into hardware Keychain.
//

import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
public final class SpotifyPKCEAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = SpotifyPKCEAuthenticator()

    public static let redirectURI = "linerios://auth-callback"
    public static let callbackScheme = "linerios"

    private let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    private let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!

    private let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-library-read",
        "user-library-modify",
        "playlist-read-private"
    ].joined(separator: " ")

    private var activeAuthSession: ASWebAuthenticationSession?
    private var pendingCodeVerifier: String?
    private var pendingAuthState: String?

    private override init() {
        super.init()
    }

    // MARK: - Authorization Flow

    public func authorize() async throws -> String {
        guard let clientId = KeychainStore.shared.get(stringForKey: .clientId), clientId.count == 32 else {
            throw AuthError.missingClientId
        }

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = UUID().uuidString

        self.pendingCodeVerifier = verifier
        self.pendingAuthState = state

        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes)
        ]

        guard let authURL = components.url else {
            throw AuthError.invalidURL
        }

        RingBufferLogger.shared.log(
            level: .info,
            category: "OAuth",
            message: "Launching ASWebAuthenticationSession for PKCE flow"
        )

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: AuthError.missingCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeAuthSession = session
            session.start()
        }

        return try await handleCallback(url: callbackURL)
    }

    // MARK: - Token Exchange

    public func handleCallback(url: URL) async throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidCallback
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            RingBufferLogger.shared.log(level: .error, category: "OAuth", message: "Spotify auth error: \(error)")
            throw AuthError.spotifyRejected(error)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingAuthorizationCode
        }

        let state = queryItems.first(where: { $0.name == "state" })?.value
        if let expectedState = self.pendingAuthState, state != expectedState {
            RingBufferLogger.shared.log(level: .error, category: "OAuth", message: "CSRF state verification failed")
            throw AuthError.stateMismatch
        }

        guard let verifier = self.pendingCodeVerifier,
              let clientId = KeychainStore.shared.get(stringForKey: .clientId) else {
            throw AuthError.missingCodeVerifier
        }

        let start = CACurrentMediaTime()
        let tokenResponse = try await exchangeCodeForTokens(
            code: code,
            verifier: verifier,
            clientId: clientId
        )
        let latency = (CACurrentMediaTime() - start) * 1000.0

        RingBufferLogger.shared.log(
            level: .info,
            category: "OAuth",
            message: "Tokens exchanged successfully",
            latencyMs: latency
        )

        saveTokens(response: tokenResponse)
        return tokenResponse.accessToken
    }

    public func validAccessToken() async throws -> String {
        if KeychainStore.shared.hasValidAccessToken(),
           let currentToken = KeychainStore.shared.get(stringForKey: .accessToken) {
            return currentToken
        }

        guard let refreshToken = KeychainStore.shared.get(stringForKey: .refreshToken),
              let clientId = KeychainStore.shared.get(stringForKey: .clientId) else {
            throw AuthError.notAuthenticated
        }

        let refreshed = try await refreshAccessToken(refreshToken: refreshToken, clientId: clientId)
        saveTokens(response: refreshed)
        return refreshed.accessToken
    }

    // MARK: - HTTP Network Calls

    private func exchangeCodeForTokens(
        code: String,
        verifier: String,
        clientId: String
    ) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier
        ]

        request.httpBody = formatURLEncodedBody(bodyParameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AuthError.tokenExchangeFailed(errorText)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func refreshAccessToken(
        refreshToken: String,
        clientId: String
    ) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]

        request.httpBody = formatURLEncodedBody(bodyParameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid HTTP response during refresh")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AuthError.tokenRefreshFailed(errorText)
        }

        var decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        // If Spotify did not return a new refresh token, retain the existing one
        if decoded.refreshToken == nil {
            decoded.refreshToken = refreshToken
        }
        return decoded
    }

    // MARK: - Crypto & Helper Utilities

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatURLEncodedBody(_ parameters: [String: String]) -> Data? {
        let pairs = parameters.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }
        return pairs.joined(separator: "&").data(using: .utf8)
    }

    private func saveTokens(response: TokenResponse) {
        KeychainStore.shared.set(string: response.accessToken, forKey: .accessToken)
        if let refresh = response.refreshToken {
            KeychainStore.shared.set(string: refresh, forKey: .refreshToken)
        }
        let expiryDate = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        KeychainStore.shared.set(date: expiryDate, forKey: .tokenExpiry)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return UIWindow()
    }
}

// MARK: - Models & Errors

public struct TokenResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public var refreshToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

public enum AuthError: LocalizedError, Sendable {
    case missingClientId
    case invalidURL
    case missingCallbackURL
    case invalidCallback
    case missingAuthorizationCode
    case stateMismatch
    case missingCodeVerifier
    case spotifyRejected(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case notAuthenticated
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientId:
            return "Spotify Client ID has not been configured."
        case .invalidURL:
            return "Unable to construct Spotify authorization URL."
        case .missingCallbackURL:
            return "Authentication session dismissed without callback."
        case .invalidCallback:
            return "Invalid callback URL received from Spotify."
        case .missingAuthorizationCode:
            return "No authorization code returned from Spotify."
        case .stateMismatch:
            return "Security state mismatch detected (possible CSRF)."
        case .missingCodeVerifier:
            return "PKCE code verifier is missing from session."
        case .spotifyRejected(let err):
            return "Spotify rejected authorization: \(err)"
        case .tokenExchangeFailed(let msg):
            return "Failed to exchange authorization code for tokens: \(msg)"
        case .tokenRefreshFailed(let msg):
            return "Failed to refresh Spotify access token: \(msg)"
        case .notAuthenticated:
            return "No valid authentication session found. Please sign in."
        case .networkError(let msg):
            return "Network communication error: \(msg)"
        }
    }
}
