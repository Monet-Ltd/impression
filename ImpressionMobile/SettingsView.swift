import SwiftUI

struct MobileSettingsView: View {
    let viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss
    private let store = SharedDataStore.shared

    @State private var refreshInterval: Double = 120
    @State private var warningThreshold: Double = 80
    @State private var criticalThreshold: Double = 95
    @State private var resetNotifications = true
    @State private var thresholdNotifications = true
    @State private var showTokenSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Refresh") {
                    Picker("Interval", selection: $refreshInterval) {
                        Text("1 min").tag(60.0)
                        Text("2 min").tag(120.0)
                        Text("5 min").tag(300.0)
                    }
                    .onChange(of: refreshInterval) { _, newValue in
                        store.refreshInterval = newValue
                    }
                }

                Section("Notifications") {
                    Toggle("Reset alerts", isOn: $resetNotifications)
                        .onChange(of: resetNotifications) { _, newValue in
                            store.resetNotificationsEnabled = newValue
                        }
                    Toggle("Threshold warnings", isOn: $thresholdNotifications)
                        .onChange(of: thresholdNotifications) { _, newValue in
                            store.thresholdNotificationsEnabled = newValue
                        }
                }

                Section("Account") {
                    HStack {
                        Text("Status")
                        Spacer()
                        switch viewModel.tokenStatus {
                        case .valid:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        case .expiresSoon(let date):
                            Label("Expires \(date, style: .relative)", systemImage: "clock")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        case .expired:
                            Label("Expired", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        case .notFound, .unknown:
                            Label("Not connected", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Button("Update Token") {
                        showTokenSheet = true
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTokenSheet) {
                TokenPasteSheet(viewModel: viewModel)
            }
            .onAppear {
                refreshInterval = store.refreshInterval
                warningThreshold = store.warningThreshold
                criticalThreshold = store.criticalThreshold
                resetNotifications = store.resetNotificationsEnabled
                thresholdNotifications = store.thresholdNotificationsEnabled
            }
        }
    }
}

struct TokenPasteSheet: View {
    let viewModel: UsageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pastedJSON = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste your credentials JSON:")
                    .font(.subheadline)

                Text("cat ~/.claude/.credentials.json")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                TextEditor(text: $pastedJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Connect") {
                    guard let data = pastedJSON.data(using: .utf8),
                          let file = try? JSONDecoder().decode(CredentialsFile.self, from: data),
                          let oauth = file.claudeAiOauth else {
                        error = "Invalid JSON"
                        return
                    }
                    viewModel.setToken(oauth.accessToken, expiresAt: oauth.expiresAtDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedJSON.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Update Token")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
