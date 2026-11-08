import SwiftUI

/// The one question Read Aloud asks before it reads: whose voice.
///
/// Asked at the moment someone first presses Listen, not on the welcome screen, because many readers
/// never use Read Aloud at all and hearing the samples is what makes the choice possible. Asked once:
/// after this, Settings is where the voice changes.
struct VoiceChooserSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The four voices in the order they are offered, Spencer first: core's default is the UK man,
    /// so that is what a reader who simply presses Choose gets. These are the names `voices()`
    /// reports, which is what the speaker and the settings store hold.
    private static let order = ["Spencer", "Russell", "Freya", "Harper"]

    @State private var chosen = "Spencer"

    private var speaker: Speaker { store.speaker }

    private var offered: [VoiceInfo] {
        let all = speaker.offered
        return Self.order.compactMap { name in all.first { $0.name == name } }
    }

    /// "British male", not "UK · male": a reader choosing a voice is choosing how the words sound.
    private func spoken(_ voice: VoiceInfo) -> String {
        let accent = voice.accent == "UK" ? "British" : "American"
        return "\(accent) \(voice.female ? "female" : "male")"
    }

    private func label(for name: String) -> String {
        offered.first { $0.name == name }?.label ?? name
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(offered, id: \.name) { voice in
                        HStack(spacing: 12) {
                            Button {
                                chosen = voice.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.label)
                                    Text(spoken(voice))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(voice.label), \(spoken(voice))")
                            .accessibilityIdentifier(voice.name)
                            .accessibilityValue(chosen == voice.name ? "Selected" : "")
                            .accessibilityAddTraits(chosen == voice.name ? [.isButton, .isSelected] : .isButton)

                            if chosen == voice.name {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }

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
                            .accessibilityLabel("Hear \(voice.label)")
                        }
                    }
                } footer: {
                    Text("Tap ▶ to hear a verse in that voice.")
                }

                Section {
                    Button {
                        speaker.voice = chosen
                        speaker.hasChosenVoice = true
                        speaker.stopAudition()
                        dismiss()
                        store.startReading()
                    } label: {
                        Text("Choose \(label(for: chosen))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("chooseVoice")
                } footer: {
                    Text("You can change this any time in Settings.")
                }
            }
            .navigationTitle("Choose a reading voice")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { speaker.stopAudition() }
        }
        .presentationDetents([.medium, .large])
    }
}
