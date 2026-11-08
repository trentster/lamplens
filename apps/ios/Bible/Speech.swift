import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Read Aloud on the phone.
///
/// The words, the trimming, the pace and the gaps all come from the shared engine in `bible-core`,
/// so the phone and the Mac say the same thing the same way. What is the phone's own is the two
/// pieces that cannot be shared: the voice ships inside the app rather than being fetched, so this
/// build carries no networking code at all, and the samples are played with Apple's audio stack
/// rather than CoreAudio directly.
///
/// One rule from the Mac carries over exactly: the voice follows the page. Anything that moves the
/// reader stops the reading.
@MainActor
@Observable
final class Speaker {
    /// How long a reading keeps going. The last choice is remembered per device.
    enum Stop: String, CaseIterable, Identifiable {
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
            case .sixtyMinutes: "60 minutes"
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
    }

    enum Phase: Equatable {
        case off
        case preparing
        case reading
        case paused
        case failed(String)

        var isOn: Bool { self != .off }
    }

    private(set) var phase: Phase = .off
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
            // A timer chosen while the reading is already running starts from now. Without this the
            // bar showed the choice and no clock, because only `start()` ever set the deadline.
            if phase.isOn, stopAfter != oldValue {
                held = nil
        deadline = stopAfter.seconds.map { Date().addingTimeInterval($0) }
            }
        }
    }

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var synth: Synth?
    private var work: Task<Void, Never>?
    private var utterances: [SpokenUtterance] = []
    private var next = 0
    /// Whether the notifications and lock-screen targets are in place. They are registered once, not
    /// once per engine.
    private var observersInstalled = false

    private var deadline: Date?
    /// Time left on the sleep timer when the reading was paused. The Mac holds the clock with the
    /// voice and puts the deadline back when play resumes; wall-clock time spent paused is not time
    /// spent listening, so a fifteen-minute timer must still leave fifteen minutes.
    private var held: TimeInterval?
    /// Names the chapter for the lock screen: "John 3".
    var chapterTitle: ((Int) -> String)?
    /// Whether a reading was under way when a call or another app took the audio, so it can resume.
    private var interrupted = false
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

    /// Starts at `chapterIndex`, saying its verses from the first word. `provider` is what lets the
    /// reading carry on into the next chapter when the timer is not the thing stopping it.
    func start(
        chapterIndex: Int, fromVerse: Int? = nil,
        provider: @escaping (Int, Int?) -> (verses: [SpokenUtterance], chapter: Int)
    ) {
        self.provider = provider
        let first = provider(chapterIndex, fromVerse)
        guard !first.verses.isEmpty else {
            phase = .failed("there is nothing here to read")
            return
        }
        chapter = first.chapter
        utterances = first.verses
        next = 0
        held = nil
        deadline = stopAfter.seconds.map { Date().addingTimeInterval($0) }
        phase = .preparing
        work?.cancel()
        work = Task { await run() }
    }

    /// What is left on the timer, straight off the clock, or nil when no clock is armed.
    var remaining: TimeInterval? {
        if let held { return held }
        guard let deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    func pause() {
        guard phase == .reading else { return }
        player?.pause()
        // The clock waits with the voice.
        if let deadline {
            held = max(0, deadline.timeIntervalSinceNow)
            self.deadline = nil
        }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        startEngineIfNeeded()
        player?.play()
        // Put the deadline back where it was left.
        if let held {
            deadline = Date().addingTimeInterval(held)
            self.held = nil
        }
        phase = .reading
    }

    /// Stops and takes the reading down: the page moved, or the reader asked it to.
    func stop() {
        work?.cancel()
        work = nil
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        format = nil
        synth = nil
        utterances = []
        next = 0
        speaking = nil
        chapter = nil
        deadline = nil
        held = nil
        phase = .off
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
    /// reading's own place on the page is untouched, so it can be started again from there.
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
                await play(pcm)
            } catch {
                phase = .failed("\(error)")
            }
            if phase == .preparing { phase = .off }
        }
    }

    /// Stops the sample, for a panel closing under it.
    func stopAudition() {
        guard auditioning != nil || phase == .preparing else { return }
        auditionWork?.cancel()
        auditionWork = nil
        auditioning = nil
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        format = nil
        phase = .off
    }

    private func auditionSamples(_ name: String) async throws -> [Float] {
        if let kept = auditions[name] { return kept }
        guard let synth = await openVoice() else { throw SpeakerError.noVoice }
        let pcm = try await makeSamples(Self.auditionText, voice: name, synth: synth).value
        auditions[name] = pcm
        return pcm
    }

    // MARK: - The loop

    private func run() async {
        guard let synth = await openVoice(), !Task.isCancelled else { return }
        var job = next < utterances.count ? makeSamples(utterances[next].text, synth: synth) : nil
        while next < utterances.count, !Task.isCancelled {
            if let deadline, Date() >= deadline {
                // A timed reading finishes the sentence it is in the middle of, then stops.
                break
            }
            let utterance = utterances[next]
            next += 1
            if let verse = utterance.verse {
                speaking = verse
                updateNowPlaying()
            }
            let pcm: [Float]
            do {
                pcm = try await (job ?? makeSamples(utterance.text, synth: synth)).value
            } catch {
                phase = .failed("\(error)")
                return
            }
            // Start the next one before this one is played: synthesis takes a fifth of a second a
            // verse, and a phone with its screen off has no other work to hide it behind.
            job = next < utterances.count ? makeSamples(utterances[next].text, synth: synth) : nil
            guard !Task.isCancelled else { return }
            phase = .reading
            updateNowPlaying()
            await play(pcm)
            if utterance.pauseMs > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(utterance.pauseMs) * 1_000_000)
            }
            if phase == .paused {
                // A pause holds the reading where it is until the reader comes back.
                while phase == .paused, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        guard !Task.isCancelled else { return }
        // The chapter is done. Keep reading walks on; anything else stops with the chapter.
        if stopAfter == .keepReading, let chapter, let provider {
            // A chapter the reading walks into starts at its first verse, and says so.
            let following = provider(chapter + 1, nil)
            if !following.verses.isEmpty {
                self.chapter = following.chapter
                utterances = following.verses
                next = 0
                await run()
                return
            }
        }
        stop()
    }


    private func makeSamples(_ text: String, synth: Synth) -> Task<[Float], Error> {
        makeSamples(text, voice: voice, synth: synth)
    }

    /// The same, in whichever voice is asked for — how a sample is made for a voice that is not the
    /// one currently chosen.
    private func makeSamples(_ text: String, voice name: String, synth: Synth) -> Task<[Float], Error> {
        Task.detached(priority: .userInitiated) { try synth.say(text, name) }
    }

    /// Opens the model once and keeps it for the session.
    private func openVoice() async -> Synth? {
        if let synth { return synth }
        phase = .preparing
        do {
            try prepareAudio()
        } catch {
            phase = .failed("the speaker could not start: \(error.localizedDescription)")
            return nil
        }
        do {
            guard let path = Self.directory?.path else { throw SpeakerError.noVoice }
            // Read the path here: `directory` is main-actor state and the model opens off it.
            let made = try await Task.detached(priority: .userInitiated) {
                Synth(try Speech.load(dir: path))
            }.value
            synth = made
            return made
        } catch {
            phase = .failed("the voice could not start: \(error)")
            return nil
        }
    }

    private func prepareAudio() throws {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // `.playback` is deliberate: a reading is the app's purpose, so it keeps going with the
        // silent switch on, the way a podcast does.
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        // Once for the life of the speaker: adding these on every engine rebuild stacked up targets
        // and observers, so one headphone tap fired play-then-pause and cancelled itself out.
        if !observersInstalled {
            observersInstalled = true
            listenForInterruptions()
            listenForAudioChanges()
            setUpRemoteCommands()
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        // The engine says 24 kHz; ask for it rather than assuming, so a change upstream is loud.
        let rate = synth?.rate ?? 24_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1) else {
            throw SpeakerError.noFormat
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
        self.format = format
    }


    /// iOS stops the audio engine for an interruption or a route change. A player node scheduled on a
    /// stopped engine never finishes its buffer, so `play`'s continuation would wait for ever and the
    /// reading would go silent with no error: start the engine again before anything is asked to play.
    private func startEngineIfNeeded() {
        guard let engine, !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    // MARK: - The lock screen

    /// What the lock screen says, and whether it offers play or pause. The verse's book and chapter
    /// come from the app, so this file does not learn how to name a chapter.
    private func updateNowPlaying() {
        guard phase.isOn, let chapter else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle?(chapter) ?? "Lamplit",
            MPMediaItemPropertyArtist: "Lamplit",
            MPNowPlayingInfoPropertyPlaybackRate: phase == .reading ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let spoken = speaking {
            info[MPMediaItemPropertyAlbumTitle] = "Verse \(spoken)"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setUpRemoteCommands() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.togglePlayPauseCommand.isEnabled = true
        centre.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.phase == .paused { self.resume() } else { self.pause() }
            }
            return .success
        }
    }

    /// A call, or another app taking the audio: stop talking, and pick up where it left off if the
    /// system says the interruption is over and the reading may carry on.
    private func listenForInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.interrupted = self.phase == .reading
                    self.player?.pause()
                    if self.phase == .reading { self.phase = .paused }
                case .ended:
                    guard self.interrupted, options.contains(.shouldResume) else { return }
                    self.interrupted = false
                    // The call took the engine with it; without this the player has nothing to play on.
                    self.startEngineIfNeeded()
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.player?.play()
                    if self.phase == .paused { self.phase = .reading }
                @unknown default:
                    break
                }
            }
        }
    }

    /// The engine can also die without an interruption: a route change tears it down, and iOS says so
    /// on its own notification rather than through the interruption one.
    private func listenForAudioChanges() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startEngineIfNeeded() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            Task { @MainActor in
                // Headphones pulled out: Apple's guidance is to pause rather than startle the room.
                if reason == .oldDeviceUnavailable {
                    self?.pause()
                } else {
                    self?.startEngineIfNeeded()
                }
            }
        }
    }

    private func play(_ samples: [Float]) async {
        guard !samples.isEmpty, let player, let format else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }
        startEngineIfNeeded()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) { done.resume() }
        }
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
