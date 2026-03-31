import SwiftUI

struct MobileContentView: View {
    let viewModel: UsageViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tokenStatus == .notFound || viewModel.tokenStatus == .unknown {
                    MobileOnboardingView(viewModel: viewModel)
                } else {
                    MobileDashboardView(viewModel: viewModel)
                }
            }
            .navigationTitle("Impression")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                MobileSettingsView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Dashboard

struct MobileDashboardView: View {
    let viewModel: UsageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Token status banner
                tokenBanner

                // Main rings
                HStack(spacing: 32) {
                    UsageRingView(
                        utilization: viewModel.snapshot.sessionUtilization,
                        label: "Session (5h)",
                        countdown: viewModel.sessionResetCountdown,
                        lineWidth: 12,
                        size: 120
                    )
                    UsageRingView(
                        utilization: viewModel.snapshot.weeklyUtilization,
                        label: "Weekly (7d)",
                        countdown: viewModel.weeklyResetCountdown,
                        lineWidth: 12,
                        size: 120
                    )
                }
                .padding(.top, 8)

                Divider()

                // Opus / Sonnet details
                VStack(spacing: 12) {
                    if let opus = viewModel.snapshot.opusUtilization {
                        UsageBarView(utilization: opus, label: "Opus (7d)")
                    }
                    if let sonnet = viewModel.snapshot.sonnetUtilization {
                        UsageBarView(utilization: sonnet, label: "Sonnet (7d)")
                    }
                }
                .padding(.horizontal)

                // Footer
                HStack {
                    if viewModel.snapshot.fetchedAt != .distantPast {
                        Text("Updated \(viewModel.snapshot.fetchedAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.fetchOnce() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .refreshable {
            await viewModel.fetchOnce()
        }
        .onAppear {
            viewModel.startPolling()
        }
    }

    @ViewBuilder
    private var tokenBanner: some View {
        switch viewModel.tokenStatus {
        case .expiresSoon(let date):
            HStack {
                Image(systemName: "clock.badge.exclamationmark")
                VStack(alignment: .leading) {
                    Text("Token expires \(date, style: .relative)")
                        .font(.caption.bold())
                    Text("Refresh in Terminal and re-paste")
                        .font(.caption2)
                }
                Spacer()
            }
            .padding(12)
            .background(.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .expired:
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("Token expired")
                        .font(.caption.bold())
                    Text("Open Settings to paste a new token")
                        .font(.caption2)
                }
                Spacer()
            }
            .padding(12)
            .background(.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        default:
            EmptyView()
        }
    }
}
