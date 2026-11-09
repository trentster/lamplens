import CoreGraphics
import Foundation

/// Where the voice is: the chapter (whole-Bible index) and the verse being said.
struct VoicePosition: Equatable {
    var chapter: Int
    var verse: Int
}

/// The page following the voice, by the Mac's rule (`Reader::follow` and `follow_move` in
/// `crates/app/src/reader/mod.rs`, with the same constants). The page moves only when the verse
/// being said is about to leave the comfortable part of the screen, so it glides now and then
/// rather than crawling on every verse. Plain arithmetic, compiled into the logic tests too.
enum FollowTheVoice {
    /// The verse may sit anywhere from the toolbar down to two-thirds of the page before the page
    /// moves. The Mac's `FOLLOW_TRIGGER`.
    static let trigger: CGFloat = 0.66
    /// When it does move, the verse lands a third of the way down, so most of the page is what
    /// comes next. The Mac's `FOLLOW_LANDING`.
    static let landing: CGFloat = 0.33
    /// After the reader scrolls, the page is theirs for this long: pulling it back while they read
    /// elsewhere would be the app arguing with the person using it. The Mac's `FOLLOW_YIELD`.
    static let yield: TimeInterval = 8

    /// How far to move the page (positive moves the text up), or `nil` when the verse is
    /// comfortably in view. `top` is where the verse starts on screen, `height` how tall it is,
    /// `toolbar` where the usable part of the page begins and `viewport` the screen's height.
    static func move(top: CGFloat, height: CGFloat, toolbar: CGFloat, viewport: CGFloat) -> CGFloat? {
        let usable = max(viewport - toolbar, 1)
        let inBand = top >= toolbar && top + height <= toolbar + usable * trigger
        if inBand { return nil }
        return top - (toolbar + usable * landing)
    }
}
