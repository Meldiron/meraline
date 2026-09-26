import SwiftUI

/// The capsule beside the pin after an update. Its label opens the notes under the input, and the cross
/// hides it until the next update. Glass with the faint pink tint of the active pin, a little stronger
/// while the notes are open.
struct WhatsNewButton: View {
    let version: String
    let isExpanded: Bool
    let toggle: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.meralinePink)
                    Text("What’s New")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .help(isExpanded ? "Hide the notes" : "What’s new in Meraline \(version)")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .help("Hide until the next update")
            .accessibilityLabel("Dismiss What’s New")
        }
        .buttonStyle(.plain)
        .frame(height: 32)
        .glassEffect(.regular.tint(.meralinePink.opacity(isExpanded ? 0.22 : 0.12)).interactive(), in: .capsule)
    }
}

/// The notes of the update the capsule announces, under the input: what Sparkle carried when it installed
/// the update, or only the way to GitHub after an install by hand. Neutral glass, like the other rows.
struct WhatsNewCard: View {
    let update: Updater.Update
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var notesHeight: CGFloat = 0

    private var blocks: [ReleaseNotes.Block] {
        update.notes.map(ReleaseNotes.blocks(from:)) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What’s new in Meraline \(update.version)")
                .font(.system(size: 13, weight: .semibold))
            if blocks.isEmpty {
                Text("Meraline was updated. Its release notes are on GitHub.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    notes
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { notesHeight = $0 }
                }
                .frame(height: min(notesHeight, 240))
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            HStack(spacing: 8) {
                Spacer()
                if let url = Bundle.main.releaseNotesURL(for: update.version) {
                    Button("Full Release Notes") { openURL(url) }
                        .buttonStyle(.glass)
                }
                Button("Got It", action: dismiss)
                    .buttonStyle(.glass(.regular.tint(.meralinePink.opacity(0.18))))
                    .help("Hide What’s New until the next update")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(MarkdownText.render(text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let text):
                    Text(MarkdownText.render(text))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
