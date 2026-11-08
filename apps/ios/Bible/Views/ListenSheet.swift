import SwiftUI

/// Read Aloud's own panel: start or stop, and which voice reads.
///
/// The timer is not here: on the Mac it is chosen from the listening bar while a reading runs, and
/// the phone does the same. Nothing needs downloading either — the voice ships inside the app.
struct ListenSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var speaker: Speaker { store.speaker }

    var body: some View {
        NavigationStack {
            List {
                readSection
                voiceSection
            }
            .navigationTitle("Read Aloud")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { speaker.stopAudition() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var readSection: some View {
        Section {
            Button {
                store.toggleReading()
                if speaker.phase.isOn { dismiss() }
            } label: {
                Label(speaker.phase.isOn ? "Stop reading" : "Start reading",
                      systemImage: speaker.phase.isOn ? "stop.fill" : "play.fill")
            }
            if let verse = speaker.speaking, let chapter = speaker.chapter {
                LabeledContent("Speaking") {
                    Text("\(chapterLabel(index: UInt16(chapter))) :\(verse)")
                }
            }
        } footer: {
            Text("The voice follows the page: choosing a chapter, a verse or another translation stops the reading.")
        }
    }

    private var voiceSection: some View {
        Section {
            ForEach(speaker.offered, id: \.name) { voice in
                HStack(spacing: 12) {
                    Button {
                        speaker.voice = voice.name
                        speaker.hasChosenVoice = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(voice.name)
                            Text("\(voice.accent) · \(voice.female ? "female" : "male") · \(voice.nativeWpm) wpm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(voice.name), \(voice.accent), \(voice.female ? "female" : "male")")
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
    }
}
