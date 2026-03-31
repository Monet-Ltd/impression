import SwiftUI
import WidgetKit

struct UsageWidgetEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeWidgetView(snapshot: entry.snapshot)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 6) {
            DualRingView(
                session: snapshot.sessionUtilization,
                weekly: snapshot.weeklyUtilization,
                sessionCountdown: formatCountdown(snapshot.sessionResetsAt),
                weeklyCountdown: formatCountdown(snapshot.weeklyResetsAt),
                outerSize: 70,
                innerSize: 42
            )
        }
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Impression")
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(snapshot.sessionUtilization))%")
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(UsageColor.from(utilization: snapshot.sessionUtilization).swiftUIColor)
            }

            HStack(spacing: 4) {
                Text("Session (5h)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let cd = formatCountdown(snapshot.sessionResetsAt) {
                    Text("Resets in \(cd)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            WidgetProgressBar(value: snapshot.sessionUtilization / 100, color: UsageColor.from(utilization: snapshot.sessionUtilization).swiftUIColor)

            HStack(spacing: 4) {
                Text("Weekly (7d)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let cd = formatCountdown(snapshot.weeklyResetsAt) {
                    Text("Resets in \(cd)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            WidgetProgressBar(value: snapshot.weeklyUtilization / 100, color: UsageColor.from(utilization: snapshot.weeklyUtilization).swiftUIColor)

            HStack(spacing: 16) {
                if let opus = snapshot.opusUtilization {
                    HStack(spacing: 4) {
                        Text("Opus")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(opus))%")
                            .font(.caption2.bold())
                            .monospacedDigit()
                    }
                }
                if let sonnet = snapshot.sonnetUtilization {
                    HStack(spacing: 4) {
                        Text("Sonnet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Int(sonnet))%")
                            .font(.caption2.bold())
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(spacing: 16) {
            Text("Impression")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 24) {
                UsageRingView(
                    utilization: snapshot.sessionUtilization,
                    label: "Session",
                    countdown: formatCountdown(snapshot.sessionResetsAt),
                    size: 100
                )
                UsageRingView(
                    utilization: snapshot.weeklyUtilization,
                    label: "Weekly",
                    countdown: formatCountdown(snapshot.weeklyResetsAt),
                    size: 100
                )
            }

            Divider()

            VStack(spacing: 8) {
                if let opus = snapshot.opusUtilization {
                    UsageBarView(utilization: opus, label: "Opus (7d)")
                }
                if let sonnet = snapshot.sonnetUtilization {
                    UsageBarView(utilization: sonnet, label: "Sonnet (7d)")
                }
            }

            Spacer()

            Text("Updated \(snapshot.fetchedAt, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Helpers

struct WidgetProgressBar: View {
    let value: Double // 0-1
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.2))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * min(value, 1))
            }
        }
        .frame(height: 4)
    }
}

private func formatCountdown(_ date: Date?) -> String? {
    guard let date, date > Date() else { return nil }
    let interval = date.timeIntervalSinceNow
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    if hours >= 24 {
        return "\(hours / 24)d \(hours % 24)h"
    }
    return "\(hours)h \(minutes)m"
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .init(
        sessionUtilization: 42, sessionResetsAt: Date().addingTimeInterval(8100),
        weeklyUtilization: 15, weeklyResetsAt: Date().addingTimeInterval(259200),
        opusUtilization: 8, sonnetUtilization: 3,
        fetchedAt: .now, source: .oauthUsage
    ))
}

#Preview("Medium", as: .systemMedium) {
    UsageWidget()
} timeline: {
    UsageEntry(date: .now, snapshot: .init(
        sessionUtilization: 85, sessionResetsAt: Date().addingTimeInterval(3600),
        weeklyUtilization: 45, weeklyResetsAt: Date().addingTimeInterval(172800),
        opusUtilization: 28, sonnetUtilization: 12,
        fetchedAt: .now, source: .oauthUsage
    ))
}
