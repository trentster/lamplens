import MediaPlayer

/// The lock screen and Control Centre: what they say about a reading, and their play and pause
/// buttons. `Speaker` updates this from one place, whenever the reading changes, so the lock screen
/// can't say playing while the voice is paused.
@MainActor
enum NowPlaying {
    private static var commandsInstalled = false

    /// "John 3", "Verse 16" and whether it is playing. The chapter is named by the app, so this file
    /// does not learn how to name one.
    static func show(title: String, verse: UInt8?, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Lamplens",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let verse {
            info[MPMediaItemPropertyAlbumTitle] = "Verse \(verse)"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// The lock screen's and headphones' buttons. Registered once for the life of the app: adding
    /// targets again stacked them up, so one headphone tap fired play-then-pause and cancelled itself
    /// out.
    static func installCommands(for speaker: Speaker) {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let centre = MPRemoteCommandCenter.shared()
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
    }
}
