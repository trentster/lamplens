import SwiftUI

/// The Mac's Read aloud list, in the Mac's order: every voice, what it sounds like, and a sample.
///
/// Shared by the Read Aloud panel and Settings → Read aloud, so the two cannot drift apart.
struct VoiceList: View {
    let theme: Theme

    @Environment(Store.self) private var store

    private var speaker: Speaker { store.speaker }

    var body: some View {
        Section {
            ForEach(speaker.offeredInOrder, id: \.name) { voice in
                HStack(spacing: 12) {
                    Button {
                        speaker.voice = voice.name
                        speaker.hasChosenVoice = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name)
                            Text(voice.voiceOrder.described)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(voice.name), \(voice.voiceOrder.described)")
                    .accessibilityValue(speaker.voice == voice.name ? "Selected" : "")
                    .accessibilityAddTraits(speaker.voice == voice.name ? [.isButton, .isSelected] : .isButton)

                    if speaker.voice == voice.name {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }

                    // Hearing a voice is how it gets chosen, so every row can say its sample.
                    Button {
                        speaker.audition(voice.name)
                    } label: {
                        if speaker.auditioning == voice.name {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.circle")
                                .font(.title3)
                                .foregroundStyle(.tint)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Hear \(voice.name)")
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Tap a play button to hear a verse in that voice.")
        }
        .listRowBackground(Color(theme.fillStrong))
    }
}
