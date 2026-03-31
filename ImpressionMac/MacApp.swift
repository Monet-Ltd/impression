import SwiftUI

@main
struct ImpressionMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — menu bar only
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}
