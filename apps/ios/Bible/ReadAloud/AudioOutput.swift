import AVFoundation

/// The phone's sound for Read Aloud: the audio session, the engine and the one player node, and what
/// to do when iOS takes them away. Apple's plumbing lives here so `Speaker` reads as the reading's
/// own steps. This class makes no decisions about the reading: a call or headphones coming out is
/// reported, and `Speaker` decides what it means.
@MainActor
final class AudioOutput {
    /// A call or another app took the audio (`began`), or gave it back, with or without leave to
    /// carry on. The player is already paused when `began` arrives.
    var onInterruption: ((_ began: Bool, _ mayResume: Bool) -> Void)?
    /// Headphones came out. Apple's guidance is to pause rather than startle the room.
    var onHeadphonesOut: (() -> Void)?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    /// The notifications are observed once for the life of the app, not once per engine: observers
    /// added on every rebuild stacked up and answered one event several times.
    private var observing = false
    /// True while a background task is bringing the engine back.
    private var restarting = false

    /// Starts the session and an engine at `sampleRate`. Does nothing when one is already running.
    func prepare(sampleRate: Double) throws {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // `.playback` is deliberate: a reading is the app's purpose, so it keeps going with the
        // silent switch on, the way a podcast does.
        Breadcrumbs.mark("activating the audio session")
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        Breadcrumbs.mark("audio session active")
        if !observing {
            observing = true
            observe()
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw SpeakerError.noFormat
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        Breadcrumbs.mark("starting the engine")
        try engine.start()
        Breadcrumbs.mark("engine started")
        player.play()
        self.engine = engine
        self.player = player
        self.format = format
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        restartIfNeeded()
        player?.play()
    }

    /// After a call: the call took the engine with it, and without this the player has nothing to
    /// play on.
    func resumeAfterInterruption() {
        restartIfNeeded()
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
    }

    /// Silences and takes everything down. The next `prepare` builds afresh.
    func stop() {
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        format = nil
    }

    /// Plays `samples` and returns when they have been heard. While the player is paused this waits,
    /// which is what holds a reading on the sentence it was in.
    func play(_ samples: [Float]) async {
        guard !samples.isEmpty, let player, let format else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }
        restartIfNeeded()
        // A buffer scheduled on a stopped engine never completes, and the reading would wait on it
        // for ever. Give the engine a moment to come back, then let this pass rather than wedge.
        var waited = 0
        while let engine, !engine.isRunning, waited < 2_000, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 50
        }
        guard engine?.isRunning == true else { return }
        Breadcrumbs.mark("scheduling \(samples.count) samples")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) { done.resume() }
        }
        Breadcrumbs.mark("buffer played")
    }

    /// iOS stops the engine for an interruption or a route change, and a player node scheduled on a
    /// stopped engine never finishes its buffer. Starting an engine blocks for as long as CoreAudio
    /// needs, and this is reached from notifications that arrive while someone is scrolling the page,
    /// so it never runs on the main actor.
    private func restartIfNeeded() {
        guard let engine, !engine.isRunning, !restarting else { return }
        Breadcrumbs.mark("restarting the engine off the main actor")
        restarting = true
        let boot = EngineBoot(engine: engine, session: AVAudioSession.sharedInstance())
        Task.detached(priority: .userInitiated) { [weak self] in
            boot.run()
            guard let self else { return }
            await MainActor.run { self.restarting = false }
        }
    }

    private func observe() {
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
                    self.player?.pause()
                    self.onInterruption?(true, false)
                case .ended:
                    self.onInterruption?(false, options.contains(.shouldResume))
                @unknown default:
                    break
                }
            }
        }
        // The engine can also die without an interruption: a route change tears it down, and iOS
        // says so on its own notification rather than through the interruption one.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartIfNeeded() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
            else { return }
            Task { @MainActor in
                guard let self else { return }
                if reason == .oldDeviceUnavailable {
                    self.onHeadphonesOut?()
                } else {
                    self.restartIfNeeded()
                }
            }
        }
    }
}

/// Holds what a restart needs, so the blocking part can happen off the main actor. `AVAudioEngine`
/// is not `Sendable`, but starting it is thread-safe and `restarting` keeps it to one task at a time.
private final class EngineBoot: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let session: AVAudioSession

    init(engine: AVAudioEngine, session: AVAudioSession) {
        self.engine = engine
        self.session = session
    }

    func run() {
        try? session.setActive(true)
        try? engine.start()
    }
}
