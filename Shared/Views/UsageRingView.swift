import SwiftUI

struct UsageRingView: View {
    let utilization: Double // 0-100
    let label: String
    let countdown: String?
    var lineWidth: CGFloat = 8
    var size: CGFloat = 84

    private var progress: Double { min(utilization / 100.0, 1.0) }
    private var percentageFontSize: CGFloat { max(floor(size * 0.22), 18) }
    private var color: Color {
        switch UsageColor.from(utilization: utilization) {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                Text("\(Int(utilization))%")
                    .font(.system(size: percentageFontSize, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-0.2)
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .frame(width: size + 8, height: 14)

            Text(countdown ?? " ")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .padding(.top, 6)
                .frame(width: size + 8, height: 18)
        }
        .frame(width: size + 8)
    }
}

struct UsageBarView: View {
    let utilization: Double
    let label: String

    private var progress: Double { min(utilization / 100.0, 1.0) }
    private var color: Color {
        switch UsageColor.from(utilization: utilization) {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 6)
        }
    }
}

struct DualRingView: View {
    let session: Double
    let weekly: Double
    let sessionCountdown: String?
    let weeklyCountdown: String?
    var outerSize: CGFloat = 100
    var innerSize: CGFloat = 60

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                UsageRingView(
                    utilization: session,
                    label: "",
                    countdown: nil,
                    lineWidth: 8,
                    size: outerSize
                )

                UsageRingView(
                    utilization: weekly,
                    label: "",
                    countdown: nil,
                    lineWidth: 6,
                    size: innerSize
                )
            }

            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("Session")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let sessionCountdown {
                        Text(sessionCountdown)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                VStack(spacing: 2) {
                    Text("Weekly")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let weeklyCountdown {
                        Text(weeklyCountdown)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        UsageRingView(utilization: 42, label: "Session", countdown: "2h 15m")
        UsageRingView(utilization: 85, label: "Weekly", countdown: "3d 5h")
        UsageBarView(utilization: 42, label: "Opus (7d)")
        DualRingView(session: 42, weekly: 15, sessionCountdown: "2h 15m", weeklyCountdown: "3d 5h")
    }
    .padding()
}
