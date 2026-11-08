import SwiftUI

/// The bar that appears while a reading is running, shaped like the Mac's: pause on the left with
/// where you are and what is happening, the stopwatch with its countdown on the right, and a close.
///
/// The timer lives here rather than in the Read Aloud panel because that is where the Mac keeps it:
/// it is a choice made while listening, not a setting for the voice. Pressing the stopwatch opens
/// the same eight rows, with a tick on the one in force.
struct ListeningBar: View {
    @Environment(Store.self) private var store
    let theme: Theme

    private var speaker: Speaker { store.speaker }
    @State private var timerOpen = false

    var body: some View {
        // Only the bar redraws, once a second: the page underneath stays exactly where it is.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Button {
                if speaker.phase == .paused {
                    speaker.resume()
                } else {
                    speaker.pause()
                }
            } label: {
                Image(systemName: speaker.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(theme.onAccent))
                    .frame(width: 40, height: 40)
                    .background(Color(theme.accentSoft), in: Circle())
            }
            .accessibilityLabel(speaker.phase == .paused ? "Resume reading" : "Pause reading")
            .accessibilityIdentifier("listenPause")

            VStack(alignment: .leading, spacing: 1) {
                Text(readingRef)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(theme.ink))
                    .lineLimit(1)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(Color(theme.ink2))
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            // The countdown is the button's own label: a 14 pt glyph alone is a small target for
            // someone listening in bed, and the time is the thing worth seeing.
            Button {
                timerOpen = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 15, weight: .medium))
                    if let left = clock {
                        Text(left)
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(Color(clock == nil ? theme.ink2 : theme.accent))
                .padding(.horizontal, 6)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop after")
            .accessibilityValue(clock ?? speaker.stopAfter.title)
            .accessibilityIdentifier("listenTimer")

            Button {
                speaker.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(theme.ink2))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop reading aloud")
            .accessibilityIdentifier("listenClose")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glass(in: Capsule(), theme: theme)
        .sheet(isPresented: $timerOpen) { timerChoices }
    }

    /// "Matthew 15:1" while a verse is being said, "Matthew 15" between them.
    private var readingRef: String {
        let chapter = speaker.chapter ?? store.position.chapter
        let base = chapterLabel(index: UInt16(clamping: chapter))
        guard let verse = speaker.speaking else { return base }
        return "\(base):\(verse)"
    }

    private var clock: String? {
        guard let left = speaker.remaining else { return nil }
        let total = Int(left.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// The eight choices in the Mac's order, with the one in force ticked.
    private var timerChoices: some View {
        NavigationStack {
            List {
                ForEach(Speaker.Stop.allCases) { choice in
                    Button {
                        speaker.stopAfter = choice
                        timerOpen = false
                    } label: {
                        HStack {
                            Text(choice.title)
                                .foregroundStyle(Color(theme.ink))
                            Spacer()
                            if choice == speaker.stopAfter {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(theme.accent))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityValue(choice == speaker.stopAfter ? "Selected" : "")
                }
            }
            .navigationTitle("Stop after")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { timerOpen = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// "Listening" or "Paused": what is actually happening, because a bar that says Listening while
    /// silent is a lie. The voice is not named here — it is chosen in the panel, and repeating it
    /// beside your own reading is one more thing to read and nothing more.
    private var status: String {
        switch speaker.phase {
        case .reading: "Listening"
        case .paused: "Paused"
        case .preparing: "Starting"
        case .off: "Ready"
        case .failed: "Ready"
        }
    }
}
