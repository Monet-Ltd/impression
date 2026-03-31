import SwiftUI

@main
struct ImpressionMobileApp: App {
    @State private var viewModel = UsageViewModel()

    var body: some Scene {
        WindowGroup {
            MobileContentView(viewModel: viewModel)
                .onAppear {
                    viewModel.loadToken()
                    Task { await viewModel.requestNotificationPermission() }
                }
        }
    }
}
