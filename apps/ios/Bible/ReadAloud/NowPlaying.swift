import MediaPlayer

/// The lock screen and Control Centre: what they say about a reading, and their play and pause
/// buttons. `Speaker` updates this from one place, whenever the reading changes, so the lock screen
/// can't say playing while the voice is paused.
@MainActor
enum NowPlaying {
    private static var commandsInstalled = false

    /// The lock screen's one item: the chapter, whether it is playing, and, when a sleep timer is
    /// running, its length and how much of it the reading has used. The chapter is named by the app,
    /// so this file does not learn how to name one — and it is the item, so nothing here changes as
    /// verses go by.
    static func show(title: String, playing: Bool, duration: TimeInterval?, elapsed: TimeInterval?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Lamplens",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        // With a timer in force the bar is the timer, and iOS counts it down on its own from these
        // two numbers and the rate: no update per second, and pausing freezes it, as the app's clock
        // holds its time while the reading is paused.
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed ?? 0
        }
        // Without artwork the lock screen shows a blank grey tile.
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The app's icon, built once: the lock screen asks for it on every update, and decoding it each
    /// time would show.
    private static let artwork: MPMediaItemArtwork? = {
        guard let image = UIImage(named: "NowPlayingArtwork") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The lock screen's and headphones' buttons. Registered once for the life of the app: adding
    /// targets again stacked them up, so one headphone tap fired play-then-pause and cancelled itself
    /// out. Everything the app cannot do is switched off, or the lock screen offers a rewind and a
    /// skip that do nothing.
    static func installCommands(for speaker: Speaker) {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let centre = MPRemoteCommandCenter.shared()
        for dead in [
            centre.skipForwardCommand, centre.skipBackwardCommand,
            centre.seekForwardCommand, centre.seekBackwardCommand,
            centre.changePlaybackPositionCommand, centre.changePlaybackRateCommand,
            centre.ratingCommand, centre.likeCommand, centre.dislikeCommand,
            centre.bookmarkCommand,
        ] {
            dead.isEnabled = false
        }
        centre.playCommand.isEnabled = true
        centre.pauseCommand.isEnabled = true
        centre.togglePlayPauseCommand.isEnabled = true
        centre.playCommand.addTarget { [weak speaker] _ in
            guard let speaker else { return .commandFailed }
            Task { @MainActor in speaker.resume() }
            return .success
        }
        centre.pauseCommand.addTarget { [weak speaker] _ in
            guard let speaker else { return .commandFailed }
            Task { @MainActor in speaker.pause() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak speaker] _ in
            guard let speaker else { return .commandFailed }
            Task { @MainActor in speaker.togglePlayPause() }
            return .success
        }
        // One verse each way: ⏮ and ⏭, which read as "the next verse", not as scrubbing.
        centre.nextTrackCommand.isEnabled = true
        centre.previousTrackCommand.isEnabled = true
        centre.nextTrackCommand.addTarget { [weak speaker] _ in
            Breadcrumbs.mark("remote: next pressed")
            guard let speaker else { return .commandFailed }
            Task { @MainActor in speaker.skip(by: 1) }
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak speaker] _ in
            Breadcrumbs.mark("remote: previous pressed")
            guard let speaker else { return .commandFailed }
            Task { @MainActor in speaker.skip(by: -1) }
            return .success
        }
    }
}
