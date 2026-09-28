import SwiftUI

/// The capsule at the top of Settings › Software Update: the channel a version went out on and the tag its GitHub
/// release has, “Stable v1.7.0” or “Beta v1.8.0-beta.1”, so a beta names the pre-release it is. A click opens that
/// release, so its notes and downloads are one click away instead of somewhere among the pre-releases. Neutral glass
/// for a stable build; a beta looks like the mode toggle's chosen segment, a pink symbol in pink-tinted glass.
struct ChannelChip: View {
    let version: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let channel = UpdateChannel(version: version)
        let tag = Bundle.releaseTag(for: version)
        let release = Bundle.main.releaseNotesURL(for: version)
        Button {
            if let release { openURL(release) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: channel.symbol)
                    .foregroundStyle(channel == .beta ? AnyShapeStyle(Color.meralinePink) : AnyShapeStyle(.secondary))
                Text(channel.title)
                    .fontWeight(.semibold)
                Text(tag)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(channel == .beta ? .regular.tint(.meralinePink.opacity(0.22)).interactive() : .regular.interactive(), in: .capsule)
        .disabled(release == nil)
        .pointerStyle(release == nil ? nil : .link)
        .help(release == nil ? "" : "Open the release of \(tag) on GitHub")
        .accessibilityLabel("\(channel.title) \(tag)")
        .accessibilityHint(release == nil ? "" : "Opens its release on GitHub")
    }
}
