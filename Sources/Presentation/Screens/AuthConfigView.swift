//
//  AuthConfigView.swift
//  LineriOS
//
//  Screen S2: Zero-secret OAuth 2.0 PKCE configuration and diagnostic inspector.
//  Allows inputting Spotify Client ID, provides copyable Redirect URI, and launches PKCE handshake.
//

import SwiftUI
import UIKit

public struct AuthConfigView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var clientIdInput: String = ""
    @State private var isAuthorizing: Bool = false
    @State private var errorMessage: String?
    @State private var showCopiedAlert: Bool = false
    @State private var isConsoleExpanded: Bool = false
    @State private var diagnosticLogs: [String] = []

    private let theme = ThemePreset.midnight

    public init() {}

    public var body: some View {
        ZStack {
            theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Title Header
                    headerSection

                    // Step 1: Copy Redirect URI Card
                    step1Card

                    // Step 2: Paste Client ID Card
                    step2Card

                    // Step 3: Authorization CTA Button
                    authorizeButton

                    // Step 4: Expandable Diagnostic Console
                    diagnosticConsoleSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Spotify Connection")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
        }
        .onAppear {
            loadExistingClientId()
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Zero-Secret PKCE Auth")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(theme.textPrimary)

            Text("Your Client ID is stored locally in the iPhone Secure Enclave. No backend, no proxy, no cloud leaks.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Step 1: Redirect URI Card
    private var step1Card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEP 1: SPOTIFY DASHBOARD URI")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textMuted)
                Spacer()
                if showCopiedAlert {
                    Text("COPIED!")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#10B981"))
                }
            }

            HStack {
                Text(SpotifyPKCEAuthenticator.redirectURI)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.bgSecondary)
                    .cornerRadius(12)

                Spacer()

                Button(action: copyRedirectURI) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("Copy")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.accentPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.accentPrimary.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Text("Register this exact URI under 'Redirect URIs' in your Spotify Developer App Settings.")
                .font(.system(size: 12))
                .foregroundColor(theme.textMuted)
        }
        .padding(18)
        .background(glassCardBackground)
    }

    // MARK: - Step 2: Client ID Input Card
    private var step2Card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEP 2: SPOTIFY CLIENT ID")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.textMuted)
                Spacer()
                Text("\(clientIdInput.count)/32")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isValidClientId ? Color(hex: "#10B981") : theme.textMuted)
            }

            HStack {
                TextField("Paste 32-character hex Client ID", text: $clientIdInput)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.bgSecondary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                !clientIdInput.isEmpty && !isValidClientId ? Color(hex: "#F43F5E") : Color.clear,
                                lineWidth: 1.5
                            )
                    )

                Button(action: pasteFromClipboard) {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(theme.accentPrimary.opacity(0.15))
                        .clipShape(Circle())
                }
            }

            if !clientIdInput.isEmpty && !isValidClientId {
                Text("Client ID must be exactly 32 hexadecimal characters (0-9, a-f).")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#F43F5E"))
            }
        }
        .padding(18)
        .background(glassCardBackground)
    }

    // MARK: - Authorize Button
    private var authorizeButton: some View {
        VStack(spacing: 8) {
            Button(action: startAuthorization) {
                HStack(spacing: 10) {
                    if isAuthorizing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: theme.bgPrimary))
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Authorize with Spotify (PKCE)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                }
                .foregroundColor(theme.bgPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isValidClientId ? theme.accentPrimary : theme.accentPrimary.opacity(0.4))
                .clipShape(Capsule())
            }
            .disabled(!isValidClientId || isAuthorizing)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F43F5E"))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Diagnostic Console Section
    private var diagnosticConsoleSection: some View {
        DisclosureGroup(
            isExpanded: $isConsoleExpanded,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(theme.specularRimColor.opacity(0.2))

                    ForEach(diagnosticLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textMuted)
                    }

                    if diagnosticLogs.isEmpty {
                        Text("No auth transactions logged yet.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.textMuted.opacity(0.6))
                    }
                }
                .padding(.top, 8)
            },
            label: {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(theme.accentPrimary)
                    Text("Auth Diagnostics Console")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
            }
        )
        .padding(18)
        .background(glassCardBackground)
    }

    // MARK: - Helpers & Actions

    private var isValidClientId: Bool {
        let pattern = "^[0-9a-fA-F]{32}$"
        return clientIdInput.range(of: pattern, options: .regularExpression) != nil
    }

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(theme.glassTintColor)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(theme.specularRimColor.opacity(0.3), lineWidth: 1)
            )
    }

    private func copyRedirectURI() {
        UIPasteboard.general.string = SpotifyPKCEAuthenticator.redirectURI
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }

    private func pasteFromClipboard() {
        if let clip = UIPasteboard.general.string {
            clientIdInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func loadExistingClientId() {
        if let saved = KeychainStore.shared.get(stringForKey: .clientId) {
            clientIdInput = saved
            appendLog("Loaded existing Client ID from Keychain: \(saved.prefix(6))...")
        }
    }

    private func startAuthorization() {
        errorMessage = nil
        isAuthorizing = true
        appendLog("Saving Client ID to hardware Keychain...")
        KeychainStore.shared.set(string: clientIdInput, forKey: .clientId)

        Task {
            do {
                appendLog("Initiating ASWebAuthenticationSession with PKCE S256 challenge...")
                let token = try await SpotifyPKCEAuthenticator.shared.authorize()
                appendLog("Successfully acquired access token: \(token.prefix(8))...")

                appendLog("Pairing SPTAppRemote local IPC socket...")
                SpotifyAppRemoteAdapter.shared.configure()
                SpotifyAppRemoteAdapter.shared.authorizeAndPlayURI("")

                try? await Task.sleep(for: .milliseconds(500))
                await PlayerStore.shared.connect()

                isAuthorizing = false
                dismiss()
            } catch {
                isAuthorizing = false
                errorMessage = error.localizedDescription
                appendLog("AUTH ERROR: \(error.localizedDescription)")
            }
        }
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        diagnosticLogs.append("[\(timestamp)] \(message)")
    }
}
