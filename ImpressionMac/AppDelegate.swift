import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    let viewModel = UsageViewModel()
    private var credentialManager: CredentialManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()

        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover
        popover.contentSize = NSSize(width: 320, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MacPopoverView(viewModel: viewModel, onQuit: { NSApp.terminate(nil) })
        )

        // Setup credential manager
        credentialManager = CredentialManager { [weak self] token, expiresAt in
            self?.viewModel.setToken(token, expiresAt: expiresAt)
            self?.viewModel.startPolling()
        }
        credentialManager?.startWatching()

        // Try loading existing token
        viewModel.loadToken()
        if viewModel.tokenStatus == .valid || viewModel.tokenStatus != .notFound {
            viewModel.startPolling()
        }

        // Request notification permission
        Task { await viewModel.requestNotificationPermission() }

        // Observe snapshot changes to update icon
        // (In a full implementation, use Combine or @Observable observation)
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
        let tintColor: NSColor

        switch UsageColor.from(utilization: utilization) {
        case .green:
            imageName = "gauge.with.dots.needle.33percent"
            tintColor = .systemGreen
        case .yellow:
            imageName = "gauge.with.dots.needle.50percent"
            tintColor = .systemYellow
        case .orange:
            imageName = "gauge.with.dots.needle.67percent"
            tintColor = .systemOrange
        case .red:
            imageName = "exclamationmark.circle.fill"
            tintColor = .systemRed
        }

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Usage") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            let configured = image.withSymbolConfiguration(config)
            button.image = configured
            button.contentTintColor = tintColor
        }

        // Tooltip with quick stats
        let session = Int(viewModel.snapshot.sessionUtilization)
        let weekly = Int(viewModel.snapshot.weeklyUtilization)
        button.toolTip = "Session: \(session)% | Weekly: \(weekly)%"
    }
}

// MARK: - Popover root view

struct MacPopoverView: View {
    let viewModel: UsageViewModel
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.tokenStatus == .notFound {
                MacOnboardingView()
            } else {
                UsageDetailView(viewModel: viewModel)
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
