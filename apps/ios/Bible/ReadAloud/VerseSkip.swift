import Foundation

/// Where the lock screen's ⏮ and ⏭ land. Plain arithmetic, so the ends of chapters — the part that
/// breaks — can be tested without a voice, a chapter or a phone.
enum VerseSkip {
    /// Apple's rule for Back: a verse still in its first seconds counts as "go to the one before it";
    /// past that, the verse says itself again.
    static let freshSeconds: TimeInterval = 3

    /// The first verse a chapter actually speaks. A chapter opens with its heading — "Matthew 18" —
    /// which carries no verse number, so `first?.verse` is nil there. That nil is what made ⏭ do
    /// nothing at the end of a chapter while working fine in the middle of one.
    static func firstVerse<C: Collection>(of verses: C) -> UInt8? where C.Element == UInt8? {
        verses.compactMap { $0 }.first
    }

    /// The last verse a chapter speaks, for the same reason at the other end: a chapter may finish
    /// on a line that carries no verse number.
    static func lastVerse<C: Collection>(of verses: C) -> UInt8? where C.Element == UInt8? {
        verses.compactMap { $0 }.last
    }

    /// One verse on, or the first verse of the next chapter. `nil` when there is nothing after this
    /// verse: the end of Revelation.
    static func forward(
        from verse: UInt8?, chapter: Int, lastVerse: UInt8?, next: (chapter: Int, first: UInt8)?
    ) -> (chapter: Int, verse: UInt8)? {
        let target = Int(verse ?? 0) + 1
        if let lastVerse, target > Int(lastVerse) {
            guard let next else { return nil }
            return (next.chapter, next.first)
        }
        return (chapter, UInt8(clamping: target))
    }

    /// One verse back, or this verse again. At a chapter's first verse — or while its heading is
    /// being read, when no verse has started — it goes to the last verse of the chapter before; where
    /// there is none, Genesis 1:1, it says that verse again.
    ///
    /// A verse that has not started yet (`beganAgo` nil) counts as just started: after a skip lands
    /// on a verse the heading is read first, and a press in that window must go further back, not
    /// repeat the chapter's start for ever.
    static func back(
        from verse: UInt8?, beganAgo: TimeInterval?, chapter: Int,
        previous: (chapter: Int, last: UInt8)?
    ) -> (chapter: Int, verse: UInt8) {
        var target: Int
        if let verse {
            let fresh = (beganAgo ?? 0) < freshSeconds
            target = fresh ? Int(verse) - 1 : Int(verse)
        } else {
            // The heading is being read and no verse has begun: back is one before this chapter.
            target = 0
        }
        if target < 1 {
            guard let previous else { return (chapter, 1) }
            return (previous.chapter, previous.last)
        }
        return (chapter, UInt8(clamping: target))
    }
}
