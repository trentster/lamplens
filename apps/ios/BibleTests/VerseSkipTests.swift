import XCTest

/// Where the lock screen's ⏮ and ⏭ land, including at the ends of chapters, which is where a skip
/// goes wrong if it is going to. `VerseSkip.swift` is compiled straight into this bundle, so these
/// run in a moment with no voice and no chapter.
final class VerseSkipTests: XCTestCase {
    /// One verse on, in the middle of a chapter.
    func testForwardGoesToTheNextVerse() {
        let target = VerseSkip.forward(from: 12, chapter: 3, lastVerse: 20, next: (4, 1))
        XCTAssertEqual(target?.chapter, 3)
        XCTAssertEqual(target?.verse, 13)
    }

    /// Off the end of a chapter: the first verse of the next one, which may not be `chapter + 1` — the
    /// core answers with the chapter it actually opened.
    func testForwardOffTheEndTakesTheNextChaptersFirstVerse() {
        let target = VerseSkip.forward(from: 20, chapter: 3, lastVerse: 20, next: (4, 1))
        XCTAssertEqual(target?.chapter, 4)
        XCTAssertEqual(target?.verse, 1)
    }

    /// The last verse of Revelation has nothing after it, so ⏭ does nothing rather than closing.
    func testForwardPastTheLastChapterDoesNothing() {
        XCTAssertNil(VerseSkip.forward(from: 21, chapter: 1188, lastVerse: 21, next: nil))
    }

    /// Back inside a verse's first seconds: the verse before it.
    func testBackInTheFirstSecondsGoesToTheVerseBefore() {
        let target = VerseSkip.back(from: 12, beganAgo: 1, chapter: 3, previous: (2, 25))
        XCTAssertEqual(target.chapter, 3)
        XCTAssertEqual(target.verse, 11)
    }

    /// Back later in a verse: it says that verse again, Apple's rule.
    func testBackAfterAFewSecondsRepeatsTheVerse() {
        let target = VerseSkip.back(from: 12, beganAgo: 7, chapter: 3, previous: (2, 25))
        XCTAssertEqual(target.chapter, 3)
        XCTAssertEqual(target.verse, 12)
    }

    /// Back at a chapter's first verse: the last verse of the chapter before.
    func testBackAtTheFirstVerseTakesThePreviousChaptersLastVerse() {
        let target = VerseSkip.back(from: 1, beganAgo: 1, chapter: 3, previous: (2, 25))
        XCTAssertEqual(target.chapter, 2)
        XCTAssertEqual(target.verse, 25)
    }

    /// Back at Genesis 1:1: that verse again, not a wrap to Revelation.
    func testBackAtTheVeryBeginningRepeatsTheFirstVerse() {
        let target = VerseSkip.back(from: 1, beganAgo: 1, chapter: 0, previous: nil)
        XCTAssertEqual(target.chapter, 0)
        XCTAssertEqual(target.verse, 1)
    }

    /// While a chapter's heading is read no verse has started: Back leaves the chapter for the one
    /// before, which is the case that repeated chapter 18's first verse for ever.
    func testBackDuringTheHeadingLeavesTheChapter() {
        let target = VerseSkip.back(from: nil, beganAgo: nil, chapter: 17, previous: (16, 28))
        XCTAssertEqual(target.chapter, 16)
        XCTAssertEqual(target.verse, 28)
    }

    /// ...and at Genesis 1:1 the heading case says verse one again, since there is nothing before it.
    func testBackDuringTheFirstChaptersHeadingRepeatsVerseOne() {
        let target = VerseSkip.back(from: nil, beganAgo: nil, chapter: 0, previous: nil)
        XCTAssertEqual(target.chapter, 0)
        XCTAssertEqual(target.verse, 1)
    }

    /// A verse that has not started yet counts as just started: pressing twice in a row always goes
    /// one verse further back, never back to the same place.
    func testBackTwiceInARowGoesOneVerseFurtherEachTime() {
        let first = VerseSkip.back(from: nil, beganAgo: nil, chapter: 17, previous: (16, 28))
        XCTAssertEqual(first.chapter, 16)
        XCTAssertEqual(first.verse, 28)

        let second = VerseSkip.back(from: 28, beganAgo: 0, chapter: 16, previous: (16, 27))
        XCTAssertEqual(second.chapter, 16)
        XCTAssertEqual(second.verse, 27)
    }

    /// Landing on a chapter's first verse and pressing at once crosses back, the roll-over case.
    func testBackJustAfterLandingOnVerseOneLeavesTheChapter() {
        let target = VerseSkip.back(from: 1, beganAgo: 0.4, chapter: 17, previous: (16, 28))
        XCTAssertEqual(target.chapter, 16)
        XCTAssertEqual(target.verse, 28)
    }

    /// Mark's sequence: the reading rolls into 18, Back crosses to 17's last verse, then Forward
    /// must cross back into 18. Forward asks the chapter for its own last verse, so a reading that
    /// now begins at 17:36 is not mistaken for a one-verse chapter.
    func testBackAcrossAChapterThenForwardAgainCrossesBack() {
        let back = VerseSkip.back(from: 1, beganAgo: 0.4, chapter: 18, previous: (chapter: 17, last: 36))
        XCTAssertEqual(back.chapter, 17)
        XCTAssertEqual(back.verse, 36)

        let forward = VerseSkip.forward(from: back.verse, chapter: back.chapter, lastVerse: 36, next: (chapter: 18, first: 1))
        XCTAssertEqual(forward?.chapter, 18)
        XCTAssertEqual(forward?.verse, 1)
    }

    /// Forward off a chapter's last verse crosses into the next one whatever the sleep timer says:
    /// a press is the listener asking to move. The plan takes no timer, which this says out loud
    /// once per row of the timer menu.
    func testForwardFromALastVerseCrossesForEveryTimerSetting() {
        for stop in ReadAloudStop.allCases {
            let landed = VerseSkip.forward(
                from: 36, chapter: 17, lastVerse: 36, next: (chapter: 18, first: 1))
            XCTAssertEqual(landed?.chapter, 18, "\(stop.rawValue)")
            XCTAssertEqual(landed?.verse, 1, "\(stop.rawValue)")
        }
    }

    /// The path the remote press actually takes, with the list a chapter really hands back: the
    /// heading first, carrying no verse number, then the verses. `firstVerse` is what ⏭ asks for the
    /// chapter after this one, and reading `.first` straight off the list returned the heading's nil
    /// — which is exactly why ⏭ worked mid-chapter and did nothing at a chapter's end.
    func testAChapterWhoseFirstLineIsItsHeadingStillOffersAVerse() {
        let chapter18: [UInt8?] = [nil, 1, 2, 3, 35, nil]
        XCTAssertNil(chapter18.first.flatMap { $0 })
        XCTAssertEqual(VerseSkip.firstVerse(of: chapter18), 1)
        XCTAssertEqual(VerseSkip.lastVerse(of: chapter18), 35)

        let landed = VerseSkip.forward(
            from: 27, chapter: 945, lastVerse: 27, next: (chapter: 946, first: 1))
        XCTAssertEqual(landed?.chapter, 946)
        XCTAssertEqual(landed?.verse, 1)
    }

    /// A chapter that ends on a line with no verse number still gives Back its last verse.
    func testATrailingLineWithNoVerseDoesNotHideTheLastVerse() {
        let chapter17: [UInt8?] = [nil, 1, 26, 27, nil]
        XCTAssertEqual(VerseSkip.lastVerse(of: chapter17), 27)
        let back = VerseSkip.back(from: 1, beganAgo: 0.2, chapter: 946, previous: (chapter: 945, last: 27))
        XCTAssertEqual(back.chapter, 945)
        XCTAssertEqual(back.verse, 27)
    }
}
