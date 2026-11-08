import Foundation

/// A short trail of what the app was doing, written where the build machine can read it off the
/// phone while the app is still stuck — the one thing a crash report cannot give us for a hang.
///
/// Off unless the app is launched with `--hang-log`, so a shipped build writes nothing. The last
/// line before a freeze names the step that never returned.
enum Breadcrumbs {
    private static let queue = DispatchQueue(label: "bible-rs.breadcrumbs")
    private static var file: URL?
    /// The last step reached, so a stall detector can name it from another thread.
    private(set) static var last = "launched"

    @MainActor
    static func startIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("--hang-log") else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("breadcrumbs.txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        file = url
        mark("launched")
        watchMainThread()
    }

    /// Records a step. Cheap enough to call around every boundary that could block.
    static func mark(_ step: String) {
        guard let file else { return }
        last = step
        let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, step)
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    /// Hops onto the main queue once a second from a background thread. When the main thread stops
    /// answering, the trail gets a line naming the last step it managed to start.
    private static func watchMainThread() {
        Thread.detachNewThread {
            var waited = 0
            while true {
                Thread.sleep(forTimeInterval: 1)
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 2) == .timedOut {
                    waited += 2
                    mark("main thread stalled \(waited)s after: \(last)")
                } else {
                    waited = 0
                }
            }
        }
    }
}
