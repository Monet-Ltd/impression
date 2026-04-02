import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Full detail view used in macOS popover and iOS/iPad main app.
struct UsageDetailView: View {
    let viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metricsCard
            metadataStrip
            if hasModelBreakdown {
                breakdownCard
            }
            if let error = viewModel.error {
                errorBanner(error)
            }
        }
        .padding(16)
        .background(backgroundTone)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Impression")
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.24)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(viewModel.providerDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.12)
                        .foregroundStyle(providerAccentColor)

                    if let plan = viewModel.snapshot.normalizedPlanName {
                        Text(plan)
                            .font(.system(size: 12, weight: .regular))
                            .tracking(-0.12)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            summaryBadge
        }
    }

    private var metricsCard: some View {
        HStack(spacing: 18) {
            UsageRingView(
                utilization: viewModel.snapshot.sessionUtilization,
                label: viewModel.snapshot.primaryLabel,
                countdown: viewModel.sessionResetCountdown,
                size: 88
            )
            .frame(maxWidth: .infinity)

            UsageRingView(
                utilization: viewModel.snapshot.weeklyUtilization,
                label: viewModel.snapshot.secondaryLabel,
                countdown: viewModel.weeklyResetCountdown,
                size: 88
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .modifier(UsageSurfaceCard(accent: providerAccentColor))
    }

    private var metadataStrip: some View {
        HStack(spacing: 10) {
            infoChip(title: "Updated", value: relativeUpdatedText, systemImage: "clock")
            infoChip(title: "Refresh", value: viewModel.refreshCadenceText, systemImage: "arrow.clockwise")
            Spacer(minLength: 0)
        }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Breakdown")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(.secondary)

            if let opus = viewModel.snapshot.opusUtilization {
                UsageBarView(utilization: opus, label: "Opus (7d)")
            }
            if let sonnet = viewModel.snapshot.sonnetUtilization {
                UsageBarView(utilization: sonnet, label: "Sonnet (7d)")
            }
        }
        .padding(12)
        .modifier(UsageSurfaceCard(accent: providerAccentColor))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .regular))
                    .tracking(-0.08)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipFillColor)
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.035), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var relativeUpdatedText: String {
        if viewModel.snapshot.fetchedAt == .distantPast {
            return "No data yet"
        }
        return viewModel.snapshot.fetchedAt.formatted(.relative(presentation: .named))
    }

    private var hasModelBreakdown: Bool {
        viewModel.snapshot.opusUtilization != nil || viewModel.snapshot.sonnetUtilization != nil
    }

    private var providerAccentColor: Color {
        Color(hex: viewModel.selectedProvider.accentHex)
    }

    private var backgroundTone: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(panelBackgroundColor)
    }

    private var summaryBadge: some View {
        HStack(spacing: 10) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(providerAccentColor)
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(viewModel.snapshot.sessionUtilization))%")
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(viewModel.sessionColor.swiftUIColor)
                Text("Session")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipFillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var panelBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(.systemGray6)
        #endif
    }

    private var chipFillColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(.systemGray5)
        #endif
    }
}

private struct UsageSurfaceCard: ViewModifier {
    let accent: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.045), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 2)
    }

    private var cardFillColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.white
        #endif
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8) & 0xFF) / 255.0
        let blue = Double(int & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
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
