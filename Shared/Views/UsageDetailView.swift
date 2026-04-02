import SwiftUI

/// Full detail view used in macOS popover and iOS/iPad main app.
struct UsageDetailView: View {
    let viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Impression")
                        .font(.headline)
                    Text(viewModel.providerDisplayName)
                        .font(.caption)
                        .foregroundStyle(providerAccentColor)
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(Int(viewModel.snapshot.sessionUtilization))%")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(viewModel.sessionColor.swiftUIColor)
            }

            // Rings
            HStack(spacing: 24) {
                UsageRingView(
                    utilization: viewModel.snapshot.sessionUtilization,
                    label: viewModel.snapshot.primaryLabel,
                    countdown: viewModel.sessionResetCountdown,
                    size: 90
                )
                UsageRingView(
                    utilization: viewModel.snapshot.weeklyUtilization,
                    label: viewModel.snapshot.secondaryLabel,
                    countdown: viewModel.weeklyResetCountdown,
                    size: 90
                )
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Opus / Sonnet bars
            if let opus = viewModel.snapshot.opusUtilization {
                UsageBarView(utilization: opus, label: "Opus (7d)")
            }
            if let sonnet = viewModel.snapshot.sonnetUtilization {
                UsageBarView(utilization: sonnet, label: "Sonnet (7d)")
            }

            // Footer
            HStack {
                if let error = viewModel.error {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    if let remainingText = viewModel.snapshot.remainingText {
                        Text(remainingText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Updated \(viewModel.snapshot.fetchedAt, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                // Token status badge for iOS
                tokenStatusBadge
            }
        }
        .padding()
    }

    @ViewBuilder
    private var tokenStatusBadge: some View {
        switch viewModel.tokenStatus {
        case .notRequired:
            Label("Local", systemImage: "terminal")
                .font(.caption2)
                .foregroundStyle(providerAccentColor)

        case .expiresSoon(let date):
            Label {
                Text("Expires \(date, style: .relative)")
                    .font(.caption2)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .foregroundStyle(.orange)

        case .expired:
            Label("Token expired", systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)

        default:
            EmptyView()
        }
    }

    private var providerAccentColor: Color {
        switch viewModel.selectedProvider {
        case .claudeCode:
            return Color(red: 0.85, green: 0.45, blue: 0.29)
        case .codexCLI:
            return Color(red: 0.06, green: 0.47, blue: 0.44)
        }
    }
}

extension UsageColor {
    var swiftUIColor: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }
}
