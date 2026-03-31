import SwiftUI

struct MacOnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Connect to Claude Code")
                .font(.headline)

            Text("Run the following command in Terminal to log in:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Text("claude login")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("claude login", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }

            Text("Impression will detect your login automatically.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }
}

#Preview {
    MacOnboardingView()
        .frame(width: 320)
}
