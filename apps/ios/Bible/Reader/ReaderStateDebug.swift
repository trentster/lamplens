#if DEBUG
import Foundation

/// Holds the live reader and store so the debugger and the breadcrumb trail can ask where the reader
/// thinks it is. Debug builds only — a release build compiles none of this file.
///
/// From LLDB, with the app running and the debugger attached:
///
///     expr -l swift -- print(lamplitReaderState())
///
enum ReaderStateDebug {
    static weak var reader: ReaderView?
    static weak var store: Store?

    /// The reader and the speaker in one line: where the page is, what the strip holds, what the
    /// scroll view is doing with touches, and what the voice is reading.
    @MainActor
    static func snapshot() -> String {
        var parts: [String] = []
        if let reader {
            parts.append(reader.debugState())
        } else {
            parts.append("reader not created yet")
        }
        if let store {
            let phase = store.speaker.phase
            parts.append(
                "speaker phase=\(phase) chosen=\(store.speaker.hasChosenVoice) "
                    + "speaking=\(store.speakingVerse.map(String.init) ?? "none") "
                    + "position=\(store.position.chapter):\(store.position.verse)")
        } else {
            parts.append("store not created yet")
        }
        return parts.joined(separator: " | ")
    }

    /// Writes the same snapshot into the breadcrumb trail once a second while the reader is being
    /// scrolled, and for a few seconds after it stops, so a freeze caught in the act shows the
    /// reader's own idea of where it is, not just the last call that was made.
    ///
    /// The freeze happens with Read Aloud off, so this follows the scrolling and not the voice.
    @MainActor
    static func followTheReaderIntoBreadcrumbs() async {
        var quietTicks = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard Breadcrumbs.isOn else { continue }
            let scrolling = reader.map { $0.isTracking || $0.isDragging || $0.isDecelerating } ?? false
            if scrolling {
                quietTicks = 0
                Breadcrumbs.mark(snapshot())
            } else if quietTicks < 4 {
                // The moment the scroll stops is the interesting one, so keep recording briefly.
                quietTicks += 1
                Breadcrumbs.mark("settled " + snapshot())
            }
        }
    }
}

/// The line to paste into the debugger. A global function so LLDB can find it by name.
///
/// The state lives on the main actor, and hopping there synchronously would deadlock against a
/// frozen main thread — the very thing being investigated — so anything else says so instead.
func lamplitReaderState() -> String {
    guard Thread.isMainThread else {
        return "not the main thread; select it first (thread select 1), then run this again"
    }
    return MainActor.assumeIsolated { ReaderStateDebug.snapshot() }
}
#endif
