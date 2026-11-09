import Foundation
import Observation
import os

/// Read Aloud on the phone.
///
/// The words, the trimming, the pace and the gaps all come from the shared engine in `bible-core`,
/// so the phone and the Mac say the same thing the same way. What is the phone's own is the two
/// pieces that cannot be shared: the voice ships inside the app rather than being fetched, so this
/// build carries no networking code at all, and the samples are played with Apple's audio stack
/// rather than CoreAudio directly.
///
/// The rules (what Play, Pause, a timer, a call or headphones may do, and what the bar says) live in
/// `ReadAloudState`, which has no audio in it and is tested on its own. This class makes the sound
/// and follows what the state allows. `state` changes in one place, and the lock screen follows
/// it from there. The sound itself is `AudioOutput`, and the lock screen is `NowPlaying`.
///
/// One rule from the Mac carries over exactly: the voice follows the page. Anything that moves the
/// reader stops the reading.
@MainActor
@Observable
final class Speaker {
    typealias Stop = ReadAloudStop
    typealias Phase = ReadAloudState.Phase

    /// Where the reading is. Every change to it passes through here, so the lock screen is updated
    /// from one place and can't fall out of step with the bar.
    private(set) var state = ReadAloudState() {
        didSet {
            if state != oldValue { updateNowPlaying() }
        }
    }

    var phase: Phase { state.phase }

    /// The verse being said right now, so the page can follow it.
    private(set) var speaking: UInt8?
    /// The chapter the reading is in, which may not be the one on screen once it carries on.
    private(set) var chapter: Int?

    var voice: String = UserDefaults.standard.string(forKey: "readAloudVoice") ?? "Spencer" {
        didSet { UserDefaults.standard.set(voice, forKey: "readAloudVoice") }
    }

    var stopAfter: Stop = Stop(rawValue: UserDefaults.standard.string(forKey: "readAloudStop") ?? "") ?? .endOfChapter {
        didSet {
            UserDefaults.standard.set(stopAfter.rawValue, forKey: "readAloudStop")
            if stopAfter != oldValue { state.choose(stopAfter, at: Date()) }
        }
    }

    /// The bar's line under the reference: Listening, Paused, Ready, or what went wrong.
    var status: String { state.status(hasSpoken: speaking != nil) }

    /// What is left on the timer, straight off the clock, or nil when no timer is in force.
    var remaining: TimeInterval? { state.clock.remaining(at: Date()) }

    /// Names the chapter for the lock screen: "John 3".
    var chapterTitle: ((Int) -> String)?

    @ObservationIgnored private let audio = AudioOutput()
    @ObservationIgnored private var hooksInstalled = false
    private var synth: Synth?
    private var work: Task<Void, Never>?
    private var utterances: [SpokenUtterance] = []
    private var next = 0
    /// Fetches a chapter's utterances and says where it is, so Keep reading can walk on.
    private var provider: ((Int, Int?) -> (verses: [SpokenUtterance], chapter: Int))?

    /// Where the voice is: shipped in the app bundle, so Read Aloud works on the first launch with
    /// no network at all. The files are fetched and checked against their pins at build time.
    static var directory: URL? {
        Bundle.main.url(forResource: "Voice", withExtension: nil)
    }

    var installed: Bool { Self.directory != nil }

    /// Whether a voice has been picked, here or in Settings. Until it has, the first press of Listen
    /// asks once: hearing a voice is how this choice gets made, and it is a bad question to ask of
    /// someone who never listens.
    var hasChosenVoice: Bool {
        get { UserDefaults.standard.bool(forKey: "readAloudVoiceChosen") }
        set { UserDefaults.standard.set(newValue, forKey: "readAloudVoiceChosen") }
    }

    /// A UI test that is about the first Listen asks for that state by name, because the answer is
    /// remembered per device and another test may already have given it.
    private static func resetChoiceIfAsked() {
        if ProcessInfo.processInfo.arguments.contains("--first-listen") {
            UserDefaults.standard.set(false, forKey: "readAloudVoiceChosen")
        }
    }

    init() { Self.resetChoiceIfAsked() }

    /// The voices offered, with the name a reader should see.
    var offered: [VoiceInfo] { voices() }

    // MARK: - Reading

    /// Opens the bar at `chapterIndex`, ready: nothing is said and no clock runs until Play, the way
    /// the Mac's `Reading::open` does. `provider` is what lets the reading carry on into the next
    /// chapter when the timer is not the thing stopping it.
    func start(
        chapterIndex: Int, fromVerse: Int? = nil,
        provider: @escaping (Int, Int?) -> (verses: [SpokenUtterance], chapter: Int)
    ) {
        silence()
        self.provider = provider
        let first = provider(chapterIndex, fromVerse)
        guard !first.verses.isEmpty else {
            state.fail(.nothingToRead)
            return
        }
        chapter = first.chapter
        utterances = first.verses
        next = 0
        speaking = nil
        state.open()
    }

    /// Play: from the start, or on from a pause.
    func resume() {
        #if DEBUG
            Breadcrumbs.mark(
                "resume asked while \(state.phase), from \(Self.callerFrames(Thread.callStackSymbols, count: 3))"
            )
        #endif
        let fromTheStart = state.phase == .ready
        guard state.play(stopAfter, at: Date()) else {
            #if DEBUG
                Breadcrumbs.mark("resume refused while \(state.phase)")
            #endif
            return
        }
        #if DEBUG
            Breadcrumbs.mark("resume: now \(state.phase)")
        #endif
        if fromTheStart || work == nil {
            work = Task { await run() }
        } else {
            audio.resume()
        }
    }

    func pause() {
        #if DEBUG
            Breadcrumbs.mark(
                "pause asked while \(state.phase), from \(Self.callerFrames(Thread.callStackSymbols, count: 3))"
            )
        #endif
        guard state.pause(at: Date()) else {
            #if DEBUG
                Breadcrumbs.mark("pause refused while \(state.phase)")
            #endif
            return
        }
        #if DEBUG
            Breadcrumbs.mark("pause: now \(state.phase)")
        #endif
        audio.pause()
    }

    /// The lock screen's and headphones' one button.
    func togglePlayPause() {
        if state.phase == .reading { pause() } else { resume() }
    }

    /// Stops and takes the reading down: the page moved, or the reader asked it to.
    func stop() {
        #if DEBUG
            // Closing a note ends the reading on the phone, and nothing in the note code calls stop().
            // Record who does, so the trail names the caller instead of the symptom.
            if state.phase.isOn {
                Breadcrumbs.mark(
                    "stop while \(state.phase) from \(Self.callerFrames(Thread.callStackSymbols))")
            }
        #endif
        silence()
        synth = nil
        utterances = []
        next = 0
        speaking = nil
        chapter = nil
        state.close()
        NowPlaying.clear()
    }

    #if DEBUG
        /// The few frames above `stop()`, trimmed to the function names. A symbol line reads
        /// "2   Bible.debug.dylib   0x0000000104a1b2c3 Speaker.stop() + 12".
        private static func callerFrames(_ symbols: [String], count: Int = 4) -> String {
            symbols.dropFirst().prefix(count).map { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                return parts.count >= 4 ? String(parts[3]) : line
            }.joined(separator: " < ")
        }
    #endif

    /// Ends the loop and the sound, leaving everything else as it is.
    private func silence() {
        work?.cancel()
        work = nil
        audio.stop()
    }

    // MARK: - Audition

    /// The words the Mac auditions voices with, word for word, so the two agree on what a voice
    /// sounds like.
    static let auditionText = "In the beginning God created the heaven and the earth."

    /// The voice being made ready right now, so its row can show that it is working.
    private(set) var auditioning: String?

    /// Samples are kept for the session: the first press of each voice costs a second, the rest are
    /// instant, and a reader comparing four voices does not wait four times.
    @ObservationIgnored private var auditions: [String: [Float]] = [:]
    @ObservationIgnored private var auditionWork: Task<Void, Never>?

    /// Says the sample in one voice, so a voice can be chosen by ear rather than by its label.
    ///
    /// A reading in progress stops first: two voices at once is not a choice anyone can make. The
    /// reading's own place on the page is untouched, so it can be started again from there. A sample
    /// never touches the reading's state: one that will not play is not a failed reading, and must
    /// not open the bar to say so.
    func audition(_ name: String) {
        stop()
        auditionWork?.cancel()
        auditioning = name
        auditionWork = Task { @MainActor in
            defer { if auditioning == name { auditioning = nil } }
            do {
                let pcm = try await auditionSamples(name)
                guard auditioning == name, !Task.isCancelled else { return }
                try prepareAudio()
                await audio.play(pcm)
            } catch {
                Log.app.error("The \(name, privacy: .public) sample would not play: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Stops the sample, for a panel closing under it. A reading started from the same panel is left
    /// alone.
    func stopAudition() {
        guard auditioning != nil || auditionWork != nil else { return }
        auditionWork?.cancel()
        auditionWork = nil
        auditioning = nil
        // A sample always has the speaker to itself (it stops any reading first), so unless a
        // reading has opened since, the sound is the sample's to take down.
        if !state.phase.isOn { audio.stop() }
    }

    private func auditionSamples(_ name: String) async throws -> [Float] {
        if let kept = auditions[name] { return kept }
        let synth = try await loadSynth()
        let pcm = try await makeSamples(Self.auditionText, voice: name, synth: synth).value
        auditions[name] = pcm
        return pcm
    }

    // MARK: - The loop

    private func run() async {
        guard let synth = await openVoice(), !Task.isCancelled else {
            Breadcrumbs.mark("run ended: no voice, or cancelled before it opened")
            return
        }
        var job = next < utterances.count ? makeSamples(utterances[next].text, synth: synth) : nil
        while !Task.isCancelled {
            if next >= utterances.count {
                // The chapter is finished. Keep reading walks into the next one; anything else stops
                // here. A loop, not a call back into run(): an all-night reading would otherwise
                // stack a frame per chapter until the thread gave out.
                guard stopAfter == .keepReading, let chapter, let provider else {
                    Breadcrumbs.mark("run ended: chapter finished, stopAfter=\(stopAfter.rawValue)")
                    break
                }
                let following = provider(chapter + 1, nil)
                guard !following.verses.isEmpty else {
                    Breadcrumbs.mark("run ended: the next chapter has nothing to read")
                    break
                }
                self.chapter = following.chapter
                utterances = following.verses
                next = 0
                job = makeSamples(utterances[0].text, synth: synth)
                continue
            }
            let utterance = utterances[next]
            var pcm: [Float]
            do {
                pcm = try await (job ?? makeSamples(utterance.text, synth: synth)).value
            } catch {
                guard !Task.isCancelled else {
                    Breadcrumbs.mark("run ended: cancelled while making samples")
                    return
                }
                audio.stop()
                Breadcrumbs.mark("run ended: the voice failed")
                state.fail(.noVoice)
                return
            }
            // A pause pressed while this sentence was being made holds it here, before any sound.
            // The loop never sets the phase itself: only Play and Pause do.
            guard await mayPlay() else {
                Breadcrumbs.mark("run ended: mayPlay said no while \(state.phase)")
                return
            }
            // The clock may fall inside this sentence: say only as far as it allows and fade the
            // last second, so a timer ends the reading instead of cutting it off. The Mac does the
            // same in `play_piece`, at 0.9 s.
            var endsTheReading = false
            if let left = remaining {
                let rate = Double(synth.rate)
                if left <= Double(pcm.count) / rate {
                    let keep = max(0, min(pcm.count, Int(left * rate)))
                    pcm.removeLast(pcm.count - keep)
                    fadeOut(&pcm, rate: rate)
                    endsTheReading = true
                }
            }
            next += 1
            if let verse = utterance.verse {
                speaking = verse
                updateNowPlaying()
            }
            // Start the next one before this one is played: synthesis takes a fifth of a second a
            // verse, and a phone with its screen off has no other work to hide it behind.
            job = next < utterances.count ? makeSamples(utterances[next].text, synth: synth) : nil
            guard !Task.isCancelled else {
                Breadcrumbs.mark("run ended: cancelled after making samples")
                return
            }
            await audio.play(pcm)
            if endsTheReading {
                Breadcrumbs.mark("run ended: the timer ran out inside a sentence")
                break
            }
            if utterance.pauseMs > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(utterance.pauseMs) * 1_000_000)
            }
        }
        guard !Task.isCancelled else {
            Breadcrumbs.mark("run ended: cancelled at the end of the loop")
            return
        }
        Breadcrumbs.mark("run ended: the loop finished, closing the reading")
        stop()
    }

    /// Holds the loop while the reading is paused. False once the reading has been closed or has
    /// failed, so the loop ends.
    private func mayPlay() async -> Bool {
        while !Task.isCancelled {
            switch state.phase {
            case .reading:
                return true
            case .paused, .ready:
                try? await Task.sleep(nanoseconds: 100_000_000)
            case .off, .failed:
                return false
            }
        }
        return false
    }

    /// How long the last sentence fades when the timer ends the reading. The Mac's `FADE_SECONDS`.
    private static let fadeSeconds = 0.9

    /// Takes the voice down to nothing over the last second, so the ending is heard as an ending.
    private func fadeOut(_ pcm: inout [Float], rate: Double) {
        let fade = min(pcm.count, Int(Self.fadeSeconds * rate))
        guard fade > 0 else { return }
        for i in (pcm.count - fade)..<pcm.count {
            pcm[i] *= Float(pcm.count - i) / Float(fade)
        }
    }

    private func makeSamples(_ text: String, synth: Synth) -> Task<[Float], Error> {
        makeSamples(text, voice: voice, synth: synth)
    }

    /// The same, in whichever voice is asked for: how a sample is made for a voice that is not the
    /// one currently chosen.
    private func makeSamples(_ text: String, voice name: String, synth: Synth) -> Task<[Float], Error> {
        Task.detached(priority: .userInitiated) { try synth.say(text, name) }
    }

    /// The reading's start: the sound, then the voice. Both are checked every time. A voice kept
    /// from a sample does not mean the sound is still up, because closing the sample took it down.
    private func openVoice() async -> Synth? {
        do {
            try prepareAudio()
        } catch {
            state.fail(.noSound)
            return nil
        }
        do {
            return try await loadSynth()
        } catch {
            guard !Task.isCancelled else { return nil }
            audio.stop()
            state.fail(.noVoice)
            return nil
        }
    }

    /// Opens the model once and keeps it until the reading is stopped.
    private func loadSynth() async throws -> Synth {
        if let synth { return synth }
        guard let path = Self.directory?.path else { throw SpeakerError.noVoice }
        // Read the path here: `directory` is main-actor state and the model opens off it.
        let made = try await Task.detached(priority: .userInitiated) {
            Synth(try Speech.load(dir: path))
        }.value
        synth = made
        return made
    }

    private func prepareAudio() throws {
        installHooks()
        // The engine says 24 kHz; ask for it rather than assuming, so a change upstream is loud.
        try audio.prepare(sampleRate: Double(synth?.rate ?? 24_000))
    }

    /// A call, headphones and the lock screen's buttons all come back through `pause`, `resume` and
    /// the state, so they follow the same rules as the bar's own buttons. Installed once.
    private func installHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true
        audio.onInterruption = { [weak self] began, mayResume in
            guard let self else { return }
            if began {
                // The player is already paused. A pause by a call holds the timer like any other,
                // and is the only kind that resumes by itself.
                self.state.pause(at: Date(), byInterruption: true)
                #if DEBUG
                    Breadcrumbs.mark("interruption began, now \(self.state.phase)")
                #endif
            } else if mayResume, self.state.resumesAfterInterruption {
                guard self.state.play(self.stopAfter, at: Date()) else { return }
                #if DEBUG
                    Breadcrumbs.mark("interruption ended, resuming, now \(self.state.phase)")
                #endif
                self.audio.resumeAfterInterruption()
            } else {
                #if DEBUG
                    Breadcrumbs.mark(
                        "interruption ended, mayResume=\(mayResume), still \(self.state.phase)")
                #endif
            }
        }
        audio.onHeadphonesOut = { [weak self] in self?.pause() }
        NowPlaying.installCommands(for: self)
    }

    // MARK: - The lock screen

    private func updateNowPlaying() {
        guard state.phase.isOn, let chapter else {
            NowPlaying.clear()
            return
        }
        NowPlaying.show(
            title: chapterTitle?(chapter) ?? "Lamplit", verse: speaking, playing: state.phase == .reading)
    }
}

/// The engine object, handed to a background task. `Speech` wraps a lock of its own, so a single
/// synthesis at a time is safe off the main actor; this only spares the Swift compiler from proving
/// something the Rust side already guarantees.
private final class Synth: @unchecked Sendable {
    private let speech: Speech

    init(_ speech: Speech) {
        self.speech = speech
    }

    /// 24 kHz mono samples, at the pace the approved voices are calibrated to.
    var rate: UInt32 { speech.sampleRate() }

    func say(_ text: String, _ voice: String) throws -> [Float] {
        try speech.say(text: text, voiceName: voice)
    }
}

enum SpeakerError: LocalizedError {
    case noFormat
    case noVoice

    var errorDescription: String? {
        switch self {
        case .noFormat: "the speaker could not be set up"
        case .noVoice: "the voice could not be opened"
        }
    }
}
