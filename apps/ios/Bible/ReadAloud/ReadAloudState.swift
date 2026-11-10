import Foundation

/// How long a reading keeps going: the timer menu's eight rows, in the Mac's order. The last choice
/// is remembered per device, as the Mac remembers it.
enum ReadAloudStop: String, CaseIterable, Identifiable {
    case endOfChapter, fiveMinutes, fifteenMinutes, thirtyMinutes, fortyFiveMinutes
    case sixtyMinutes, twoHours, keepReading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .endOfChapter: "End of chapter"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .fortyFiveMinutes: "45 minutes"
        // Mark: it sits beside "2 hours". The raw value stays sixtyMinutes, so saved choices and
        // the UI tests identifiers do not move.
        case .sixtyMinutes: "1 hour"
        case .twoHours: "2 hours"
        case .keepReading: "Keep reading"
        }
    }

    /// How long it runs, or `nil` when there is no clock: the end of the chapter, or for ever.
    var seconds: TimeInterval? {
        switch self {
        case .endOfChapter, .keepReading: nil
        case .fiveMinutes: 5 * 60
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .fortyFiveMinutes: 45 * 60
        case .sixtyMinutes: 60 * 60
        case .twoHours: 2 * 60 * 60
        }
    }

    /// Whether a reading walks on into the next chapter when this one ends. "Keep reading" always
    /// does and "End of chapter" never does; a timer does while it still has time left, so it is a
    /// sleep timer and not a cap: fifteen minutes on a four-minute chapter reads for fifteen minutes.
    /// The Mac's `carry_on` in `read_aloud/reading.rs`.
    func carriesOn(timeLeft: TimeInterval?) -> Bool {
        switch self {
        case .keepReading: true
        case .endOfChapter: false
        default: (timeLeft ?? 0) > 0
        }
    }
}

/// The sleep timer's clock: idle, running towards a moment, or held with time left while the
/// reading is paused. Time spent paused is not time spent listening, so a fifteen-minute timer
/// still leaves fifteen minutes. One value, where there used to be a deadline and a held time that
/// had to be kept in step by hand in four places.
struct SleepClock: Equatable {
    enum State: Equatable {
        /// No timer: End of chapter, Keep reading, or nothing armed yet.
        case idle
        case running(until: Date)
        case held(TimeInterval)
    }

    private(set) var state: State = .idle

    /// Time left, or `nil` when no timer is in force.
    func remaining(at now: Date) -> TimeInterval? {
        switch state {
        case .idle: nil
        case .running(let until): max(0, until.timeIntervalSince(now))
        case .held(let left): left
        }
    }

    /// Runs for `seconds` from `now`, or goes idle for `nil`.
    mutating func run(for seconds: TimeInterval?, from now: Date) {
        state = seconds.map { .running(until: now.addingTimeInterval($0)) } ?? .idle
    }

    /// Holds `seconds`, ready for Play, or goes idle for `nil`.
    mutating func hold(_ seconds: TimeInterval?) {
        state = seconds.map { .held($0) } ?? .idle
    }

    /// Stops a running clock where it is, keeping the time it had left.
    mutating func stop(at now: Date) {
        if case .running(let until) = state {
            state = .held(max(0, until.timeIntervalSince(now)))
        }
    }

    /// Starts a held clock again from `now`. An idle clock stays idle.
    mutating func restart(from now: Date) {
        if case .held(let left) = state {
            state = .running(until: now.addingTimeInterval(left))
        }
    }

    mutating func clear() {
        state = .idle
    }
}

/// Where a reading is, and the one place that decides what may happen next: Play, Pause, a timer
/// choice, a call, headphones coming out. Plain values and no audio, so every rule can be tested in
/// a second. `Speaker` makes the sound and follows what this allows.
///
/// The rules are the Mac's (`crates/app/src/read_aloud/reading.rs`): the bar opens ready and waits
/// for Play, the timer starts on Play, a pause holds the time left, and a timer chosen while paused
/// replaces it.
struct ReadAloudState: Equatable {
    enum Phase: Equatable {
        /// No reading: the bar is closed.
        case off
        /// The bar is open and nothing has been played: Play starts it.
        case ready
        /// Play has been pressed: the voice is speaking, or making the next sentence to speak.
        case reading
        /// Stopped partway, by the reader, a call or headphones coming out.
        case paused
        /// Something went wrong. The bar says what in plain words and offers to try again.
        case failed(Failure)

        var isOn: Bool { self != .off }
    }

    enum Failure: Equatable {
        case nothingToRead
        case noSound
        case noVoice

        /// What the bar says: plain words, because nobody can act on an error code at bedtime.
        var message: String {
            switch self {
            case .nothingToRead: "Nothing here to read"
            case .noSound: "Couldn’t start the sound"
            case .noVoice: "Couldn’t start the voice"
            }
        }
    }

    private(set) var phase: Phase = .off
    private(set) var clock = SleepClock()
    /// A call or another app paused the reading, so it carries on when the system says it may. A
    /// pause the reader chose stays paused.
    private(set) var resumesAfterInterruption = false

    /// Opens the bar, ready, with no clock running: the Mac's `Reading::open`.
    mutating func open() {
        phase = .ready
        clock.clear()
        resumesAfterInterruption = false
    }

    /// Play. From the start the timer runs for the full time chosen; after a pause it runs on with
    /// the time it was holding. Returns false when there is nothing to play.
    @discardableResult
    mutating func play(_ stop: ReadAloudStop, at now: Date) -> Bool {
        switch phase {
        case .ready:
            clock.run(for: stop.seconds, from: now)
        case .paused:
            clock.restart(from: now)
        case .off, .reading, .failed:
            return false
        }
        phase = .reading
        resumesAfterInterruption = false
        return true
    }

    /// Pause, holding the time left. Only a reading can pause: before Play there is nothing to hold.
    @discardableResult
    mutating func pause(at now: Date, byInterruption: Bool = false) -> Bool {
        guard phase == .reading else { return false }
        clock.stop(at: now)
        phase = .paused
        resumesAfterInterruption = byInterruption
        return true
    }

    /// A row chosen from the timer menu, as the Mac's `Reading::choose`: while reading it runs from
    /// now; while paused it replaces the time held; before Play, Play arms it.
    mutating func choose(_ stop: ReadAloudStop, at now: Date) {
        switch phase {
        case .reading: clock.run(for: stop.seconds, from: now)
        case .paused: clock.hold(stop.seconds)
        case .off, .ready, .failed: break
        }
    }

    mutating func fail(_ failure: Failure) {
        phase = .failed(failure)
        clock.clear()
        resumesAfterInterruption = false
    }

    mutating func close() {
        phase = .off
        clock.clear()
        resumesAfterInterruption = false
    }

    /// The bar's line under the reference, by the Mac's rule (`listening_text`): Listening while
    /// playing, Paused once something has been said, Ready before that.
    func status(hasSpoken: Bool) -> String {
        switch phase {
        case .reading: "Listening"
        case .paused: hasSpoken ? "Paused" : "Ready"
        case .ready, .off: "Ready"
        case .failed(let failure): failure.message
        }
    }
}
