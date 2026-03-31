import SwiftUI
import WidgetKit

#if os(iOS)
struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            LockScreenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Session")
        .description("Quick session usage on lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenWidgetEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularLockScreenView(snapshot: entry.snapshot)
        case .accessoryRectangular:
            RectangularLockScreenView(snapshot: entry.snapshot)
        default:
            CircularLockScreenView(snapshot: entry.snapshot)
        }
    }
}

struct CircularLockScreenView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        Gauge(value: snapshot.sessionUtilization, in: 0...100) {
            Text("S")
        } currentValueLabel: {
            Text("\(Int(snapshot.sessionUtilization))")
                .font(.system(.body, design: .rounded).bold())
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

struct RectangularLockScreenView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Session")
                    .font(.caption2)
                Spacer()
                Text("\(Int(snapshot.sessionUtilization))%")
                    .font(.caption2.bold())
                    .monospacedDigit()
            }
            Gauge(value: snapshot.sessionUtilization, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)

            HStack {
                Text("Weekly")
                    .font(.caption2)
                Spacer()
                Text("\(Int(snapshot.weeklyUtilization))%")
                    .font(.caption2.bold())
                    .monospacedDigit()
            }
            Gauge(value: snapshot.weeklyUtilization, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
        }
    }
}
#endif
