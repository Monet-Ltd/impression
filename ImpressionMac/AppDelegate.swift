import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    let viewModel = UsageViewModel()
    private var credentialManager: CredentialManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        NSUserNotificationCenter.default.delegate = self

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()
        viewModel.onSnapshotChanged = { [weak self] in
            Task { @MainActor in
                self?.updateMenuBarIcon()
            }
        }

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover
        popover.contentSize = NSSize(width: 372, height: 438)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MacPopoverView(viewModel: viewModel, onQuit: { NSApp.terminate(nil) })
        )

        // Try loading existing token first, before CredentialManager fires its callback
        viewModel.loadToken()
        if !viewModel.requiresOnboarding {
            viewModel.startPolling()
        }

        // Setup credential manager; setToken handles startPolling when token changes
        credentialManager = CredentialManager { [weak self] token, expiresAt in
            Task { @MainActor [weak self] in
                self?.viewModel.setToken(token, expiresAt: expiresAt)
            }
        }
        credentialManager?.startWatching()

        // Request notification permission
        Task {
            let granted = await viewModel.requestNotificationPermission()
            NSLog("[Impression] Notification permission: \(granted)")
        }

        // Log startup status
        NSLog("[Impression] App launched. Token status: \(viewModel.tokenStatus)")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let utilization = viewModel.snapshot.sessionUtilization
        let imageName: String

        switch UsageColor.from(utilization: utilization) {
        case .green:
            imageName = "gauge.with.dots.needle.33percent"
        case .yellow:
            imageName = "gauge.with.dots.needle.50percent"
        case .orange:
            imageName = "gauge.with.dots.needle.67percent"
        case .red:
            imageName = "exclamationmark.circle.fill"
        }

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Usage") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            button.image = configured
            button.contentTintColor = nil
        }

        // Tooltip with quick stats
        let session = Int(viewModel.snapshot.sessionUtilization)
        let weekly = Int(viewModel.snapshot.weeklyUtilization)
        button.toolTip = """
        \(viewModel.providerDisplayName)
        Session \(session)% • Weekly \(weekly)%
        \(viewModel.sourceDisplayName)
        """
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }
}

// MARK: - Popover root view

struct MacPopoverView: View {
    let viewModel: UsageViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Provider", selection: Binding(
                get: { viewModel.selectedProvider },
                set: { viewModel.selectProvider($0) }
            )) {
                ForEach(UsageProviderKind.allCases) { provider in
                    Text(provider.shortName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if viewModel.requiresOnboarding {
                MacOnboardingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                UsageDetailView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            Divider()

            HStack {
                Button(action: {
                    Task { await viewModel.fetchOnce() }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 372, height: 438)
        .background(.regularMaterial)
    }
}
