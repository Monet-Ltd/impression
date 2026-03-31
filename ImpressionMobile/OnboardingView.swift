import SwiftUI

struct MobileOnboardingView: View {
    let viewModel: UsageViewModel
    @State private var selectedPath: OnboardingPath?
    @State private var pastedJSON = ""
    @State private var parseError: String?
    @State private var isConnected = false

    enum OnboardingPath {
        case macSync
        case pasteToken
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Monitor Claude Code Usage")
                .font(.title2.bold())

            Text("How do you use Claude Code?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if selectedPath == nil {
                // Choice buttons
                VStack(spacing: 12) {
                    Button {
                        selectedPath = .macSync
                    } label: {
                        HStack {
                            Image(systemName: "laptopcomputer")
                            VStack(alignment: .leading) {
                                Text("On my Mac")
                                    .font(.subheadline.bold())
                                Text("Sync automatically via iCloud")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedPath = .pasteToken
                    } label: {
                        HStack {
                            Image(systemName: "terminal")
                            VStack(alignment: .leading) {
                                Text("On Linux / Other")
                                    .font(.subheadline.bold())
                                Text("Paste token manually")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            } else if selectedPath == .macSync {
                macSyncView
            } else if selectedPath == .pasteToken {
                pasteTokenView
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Mac Sync

    private var macSyncView: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(.blue)

            Text("Install Impression on your Mac")
                .font(.subheadline.bold())

            Text("Your token will sync automatically via iCloud Keychain. Make sure you're signed into the same iCloud account on both devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.tokenStatus == .valid {
                Label("Connected!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                ProgressView("Waiting for iCloud sync...")
                    .font(.caption)
            }

            Button("Back") {
                selectedPath = nil
            }
            .font(.caption)
        }
        .onAppear {
            // Poll for token arrival
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { timer in
                viewModel.loadToken()
                if viewModel.tokenStatus == .valid {
                    timer.invalidate()
                    viewModel.startPolling()
                }
            }
        }
    }

    // MARK: - Paste Token

    private var pasteTokenView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 1")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)

                Text("Run this in your terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("cat ~/.claude/.credentials.json")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Step 2")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)

                Text("Paste the entire JSON output:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pastedJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )

                if let parseError {
                    Text(parseError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Button {
                connectWithPastedJSON()
            } label: {
                Text("Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pastedJSON.isEmpty)

            if isConnected {
                Label("Connected!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button("Back") {
                selectedPath = nil
                pastedJSON = ""
                parseError = nil
            }
            .font(.caption)
        }
    }

    private func connectWithPastedJSON() {
        parseError = nil

        guard let data = pastedJSON.data(using: .utf8) else {
            parseError = "Invalid text"
            return
        }

        do {
            let creds = try JSONDecoder().decode(CredentialsFile.self, from: data)
            guard let oauth = creds.claudeAiOauth else {
                parseError = "No claudeAiOauth found in JSON"
                return
            }

            viewModel.setToken(oauth.accessToken, expiresAt: oauth.expiresAtDate)
            isConnected = true
            viewModel.startPolling()
        } catch {
            parseError = "Failed to parse JSON: \(error.localizedDescription)"
        }
    }
}
