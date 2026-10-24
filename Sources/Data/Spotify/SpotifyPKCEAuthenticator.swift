//
//  SpotifyPKCEAuthenticator.swift
//  LineriOS
//
//  RFC 7636 OAuth 2.0 PKCE authentication client using ASWebAuthenticationSession + CryptoKit.
//  Operates without client secrets or backend servers, persisting tokens into hardware Keychain.
//

import Foundation
import UIKit
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

        return try await withCheckedThrowingContinuation { continuation in
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

                Task { @MainActor in
                    do {
                        let token = try await self.exchangeCodeForToken(callbackURL: callbackURL)
                        continuation.resume(returning: token)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeAuthSession = session
            session.start()
        }
    }

    public func handleCallbackURL(_ url: URL) {
        // Fallback for custom URL scheme deep links (linerios://auth-callback?code=...)
        Task {
            _ = try? await exchangeCodeForToken(callbackURL: url)
        }
    }

    // MARK: - Token Exchange & Refresh Flow

    public func exchangeCodeForToken(callbackURL: URL) async throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw AuthError.invalidCallback
        }

        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            throw AuthError.spotifyRejected(errorParam)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingAuthorizationCode
        }

        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == self.pendingAuthState else {
            throw AuthError.stateMismatch
        }

        guard let verifier = self.pendingCodeVerifier else {
            throw AuthError.missingCodeVerifier
        }

        guard let clientId = KeychainStore.shared.get(stringForKey: .clientId) else {
            throw AuthError.missingClientId
        }

        let tokens = try await postTokenExchange(
            code: code,
            codeVerifier: verifier,
            clientId: clientId
        )

        saveTokens(response: tokens)
        RingBufferLogger.shared.log(level: .info, category: "Auth", message: "OAuth PKCE token exchange successful")
        return tokens.accessToken
    }

    public func validAccessToken() async throws -> String {
        if KeychainStore.shared.hasValidAccessToken(),
           let token = KeychainStore.shared.get(stringForKey: .accessToken) {
            return token
        }

        guard let refreshToken = KeychainStore.shared.get(stringForKey: .refreshToken) else {
            throw AuthError.notAuthenticated
        }

        guard let clientId = KeychainStore.shared.get(stringForKey: .clientId) else {
            throw AuthError.missingClientId
        }

        let tokens = try await postRefreshToken(
            refreshToken: refreshToken,
            clientId: clientId
        )

        saveTokens(response: tokens)
        RingBufferLogger.shared.log(level: .info, category: "Auth", message: "OAuth token refreshed successfully")
        return tokens.accessToken
    }

    // MARK: - Network Token Requests

    private func postTokenExchange(
        code: String,
        codeVerifier: String,
        clientId: String
    ) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientId,
            "code_verifier": codeVerifier
        ]

        request.httpBody = formatURLEncodedBody(bodyParameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid HTTP response during token exchange")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AuthError.tokenExchangeFailed(errorText)
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func postRefreshToken(
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

    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
            return UIWindow()
        }
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
            return "Missing authorization callback URL."
        case .invalidCallback:
            return "Received invalid callback parameters."
        case .missingAuthorizationCode:
            return "Missing OAuth authorization code in callback."
        case .stateMismatch:
            return "OAuth state mismatch: potential CSRF attack detected."
        case .missingCodeVerifier:
            return "Missing PKCE code verifier in memory."
        case .spotifyRejected(let msg):
            return "Spotify authorization rejected: \(msg)"
        case .tokenExchangeFailed(let msg):
            return "PKCE token exchange failed: \(msg)"
        case .tokenRefreshFailed(let msg):
            return "Token refresh failed: \(msg)"
        case .notAuthenticated:
            return "No active Spotify session found."
        case .networkError(let msg):
            return "Authentication network error: \(msg)"
        }
    }
}
