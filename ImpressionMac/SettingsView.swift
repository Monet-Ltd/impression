import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let viewModel: UsageViewModel
    private let store = SharedDataStore.shared

    @State private var refreshInterval: Double = 120
    @State private var warningThreshold: Double = 80
    @State private var criticalThreshold: Double = 95
    @State private var resetNotifications = true
    @State private var thresholdNotifications = true
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Source", selection: Binding(
                    get: { viewModel.selectedProvider },
                    set: { viewModel.selectProvider($0) }
                )) {
                    ForEach(UsageProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            }

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

                if thresholdNotifications {
                    HStack {
                        Text("Warning at")
                        Slider(value: $warningThreshold, in: 50...95, step: 5)
                        Text("\(Int(warningThreshold))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    .onChange(of: warningThreshold) { _, newValue in
                        store.warningThreshold = newValue
                    }

                    HStack {
                        Text("Critical at")
                        Slider(value: $criticalThreshold, in: 80...100, step: 5)
                        Text("\(Int(criticalThreshold))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    .onChange(of: criticalThreshold) { _, newValue in
                        store.criticalThreshold = newValue
                    }
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        try? SMAppService.mainApp.register()
                    }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Provider", value: viewModel.providerDisplayName)
                LabeledContent("Token", value: viewModel.selectedProvider.requiresToken && viewModel.tokenStatus == .valid ? "Connected" : (viewModel.selectedProvider.requiresToken ? "Not connected" : "Not required"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .onAppear {
            refreshInterval = store.refreshInterval
            warningThreshold = store.warningThreshold
            criticalThreshold = store.criticalThreshold
            resetNotifications = store.resetNotificationsEnabled
            thresholdNotifications = store.thresholdNotificationsEnabled
        }
    }
}
