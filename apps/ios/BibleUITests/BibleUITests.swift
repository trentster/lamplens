import XCTest

/// The main flows, driven through the interface. Each test starts the app with no saved data
/// (`--uitest`), so it opens at John 1 in the KJV.
final class BibleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
    }

    private var reference: XCUIElement { app.buttons["reference"] }

    /// A book row in the picker, scrolled to if it is not on screen yet.
    ///
    /// The picker opens with the book you are reading expanded and centred, so a book later in the
    /// canon needs scrolling down to. Swipe **up** only: a downward drag on a sheet pulls it closed,
    /// which reads as "the book list is empty" and wastes an afternoon.
    private func bookRow(_ name: String) -> XCUIElement {
        // Rows carry a fixed identity, so wording can change without breaking this: "book-42" is
        // John whatever its label says. The name is only a fallback while the identity settles.
        let byId = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'book-' AND label BEGINSWITH %@", name + ",")).firstMatch
        let row = byId
        if row.waitForExistence(timeout: 2) { return row }
        for _ in 0..<10 where !row.exists {
            app.swipeUp(velocity: .fast)
        }
        return row
    }

    private func verse(_ id: String) -> XCUIElement { app.staticTexts[id] }

    /// Types a reference into the toolbar's field and waits for the page to move.
    private func jump(_ typed: String) {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(typed + "\n")
    }

    /// Waits for the toolbar to name a chapter.
    private func expectChapter(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = NSPredicate(format: "label BEGINSWITH %@", title + ".")
        let found = XCTNSPredicateExpectation(predicate: shown, object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed, "expected \(title), saw \(reference.label)", file: file, line: line)
    }

    func testOpensAtJohnOne() {
        expectChapter("John 1")
        XCTAssertTrue(verse("John 1:1").exists)
        XCTAssertTrue(verse("John 1:1").label.contains("In the beginning was the Word"))
    }

    func testScrollingReadsOnIntoTheNextChapters() {
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        let title = reference.label
        XCTAssertFalse(title.hasPrefix("John 1."), "still at \(title)")
        XCTAssertTrue(title.hasPrefix("John"), "left John: \(title)")
        // And back, across the chapter boundary into Luke.
        for _ in 0..<24 { app.swipeDown(velocity: .fast) }
        let shown = NSPredicate(format: "label BEGINSWITH 'Luke'")
        let back = XCTNSPredicateExpectation(predicate: shown, object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed, "saw \(reference.label)")
    }

    func testJumpsToATypedReference() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").waitForExistence(timeout: 3))
        XCTAssertTrue(verse("Romans 8:28").isHittable)
    }

    func testRotatingKeepsYourPlace() {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").waitForExistence(timeout: 3))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            expectChapter("Romans 8")
            XCTAssertTrue(verse("Romans 8:28").isHittable, "Romans 8:28 left the screen at orientation \(orientation.rawValue)")
        }
    }

    func testPicksABookAndChapter() {
        reference.tap()
        let romans = bookRow("Romans")
        XCTAssertTrue(romans.waitForExistence(timeout: 5), "Romans is not in the book list")
        romans.tap()
        let twelve = app.buttons["Romans 12"]
        if !twelve.waitForExistence(timeout: 3) {
            // The chapter grid sits under the book row; a phone can need a nudge to show it.
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(twelve.waitForExistence(timeout: 3), "Romans offers no chapter 12")
        // A chapter brings its verses up, the way the Mac's picker does; the verse is what goes there.
        twelve.tap()
        let firstVerse = app.buttons["Romans 12:1"]
        XCTAssertTrue(firstVerse.waitForExistence(timeout: 3), "Romans 12 offers no verses")
        firstVerse.tap()
        expectChapter("Romans 12")
        XCTAssertTrue(
            verse("Romans 12:1").label.contains("living sacrifice"),
            "the page did not open at Romans 12:1"
        )
    }

    func testPsalmsOpenFromAReference() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("ps 23\n")
        expectChapter("Psalm 23")
        XCTAssertTrue(verse("Psalm 23:1").waitForExistence(timeout: 3))
        XCTAssertTrue(verse("Psalm 23:1").label.contains("shepherd"))
    }

    func testSwitchesTranslation() {
        XCTAssertTrue(verse("John 1:5").label.contains("shineth in darkness"))
        app.buttons["translation"].tap()
        let web = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'WEB'")).firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 3))
        web.tap()
        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'shines in the darkness'"), object: verse("John 1:5"))
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 5), .completed, verse("John 1:5").label)
        expectChapter("John 1")
    }

    func testReopensWhereYouLeftOff() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        app.buttons["translation"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BSB'")).firstMatch.tap()

        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launchArguments = ["--uitest", "--keep-data"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").isHittable)
        XCTAssertTrue(app.buttons["translation"].label.contains("Berean"), app.buttons["translation"].label)
    }

    func testSearchFindsAndOpensAVerse() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("love one another")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 13:34'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        hit.tap()
        expectChapter("John 13")
        XCTAssertTrue(verse("John 13:34").isHittable)
    }

    func testSearchLoadsMoreAsYouScroll() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("lamb\n")
        XCTAssertTrue(row("Genesis 21:28").waitForExistence(timeout: 5))
        // The last of 175 hits, on the fourth page.
        let last = row("Revelation 22:3")
        for _ in 0..<40 where !last.exists { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(last.exists)
    }

    func testMisspelledSearchOffersASuggestion() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("bethsaida pool")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Search “bethesda pool”'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 5:2'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testHighlightBookmarkAndNoteShowInStudy() {
        let first = verse("John 1:1")
        first.tap()
        app.selectionAction("Highlight Green").tap()

        first.tap()
        app.selectionAction("Bookmark").tap()

        verse("John 1:3").tap()
        app.selectionAction("Note").tap()
        let note = app.textFields["Write a note"].exists ? app.textFields["Write a note"] : app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.typeText("All things, without exception.")
        app.buttons["Save"].tap()

        app.buttons["study"].tap()
        XCTAssertTrue(row("John 1:1").waitForExistence(timeout: 3), "bookmark listed")
        app.buttons["Highlights"].tap()
        XCTAssertTrue(row("John 1:1").waitForExistence(timeout: 3), "highlight listed")
        app.buttons["Notes"].tap()
        XCTAssertTrue(row("John 1:3").waitForExistence(timeout: 3), "note listed")
        XCTAssertTrue(row("John 1:3").label.contains("without exception"))
    }

    func testCopiesAVerseWithItsReference() {
        verse("John 1:4").tap()
        app.selectionAction("Copy").tap()
        XCTAssertTrue(app.staticTexts["Copied John 1:4"].waitForExistence(timeout: 3))
    }

    func testThemeAndTextSizeApplyAtOnce() {
        app.buttons["settings"].tap()
        // Settings follows the Mac's order, so Appearance sits below Reading and a Form does not
        // build rows that are still below the fold: scroll to it the way a reader would.
        let dark = app.buttons["Dark theme"]
        for _ in 0..<4 where !dark.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(dark.waitForExistence(timeout: 5), "Settings offers no appearance swatches")
        dark.tap()
        let slider = app.sliders["Text size"]
        for _ in 0..<4 where !slider.exists {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 3), "Settings offers no text size")
        slider.adjust(toNormalizedSliderPosition: 0.9)
        app.buttons["Done"].tap()
        XCTAssertTrue(verse("John 1:1").exists)
    }

    /// Tapping Read opens the bar paused, as the Mac's Reading::open does: nothing is said and no
    /// clock runs until Play. What the timer says is the remembered choice, shown, not started.
    private func openTheBar() {
        app.buttons["listen"].tap()
        if app.buttons["chooseVoice"].waitForExistence(timeout: 4) {
            app.buttons["chooseVoice"].tap()
        }
        XCTAssertTrue(app.buttons["listenPause"].waitForExistence(timeout: 15), "the bar did not appear")
    }

    /// A timer choice, picked from the menu: iOS draws those rows, so they are found by the words
    /// they say rather than by an identifier of ours. The menu closes on the pick, as menus do.
    /// Opens the timer menu and picks a row. The rows are iOS's own, so they are found by the words
    /// they say. A menu that has landed badly can leave a row out of reach, so one retry is allowed
    /// after closing it again: the tests are about what the choice does, not about a popover's luck.
    private func chooseTimer(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 {
            let bar = app.buttons["listenTimer"]
            XCTAssertTrue(bar.waitForExistence(timeout: 10), "no timer on the bar", file: file, line: line)
            bar.tap()
            let row = app.buttons[title]
            if row.waitForExistence(timeout: 5) {
                let reachable = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "isHittable == true"), object: row)
                if XCTWaiter.wait(for: [reachable], timeout: 3) == .completed {
                    row.tap()
                    return
                }
            }
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
        XCTFail("the timer menu never offered a tappable \(title)", file: file, line: line)
    }


    private func clockValue() -> String {
        (app.buttons["listenTimer"].value as? String) ?? ""
    }

    func testReadOpensPausedAndWaitsForPlay() {
        openTheBar()
        XCTAssertEqual(
            app.buttons["listenPause"].label, "Resume reading",
            "the bar should open paused, showing Play")
        XCTAssertTrue(app.buttons["listenTimer"].exists, "the timer belongs on the bar")
        XCTAssertFalse(clockValue().contains(":"), "no clock may run before Play (saw \(clockValue()))")
    }

    func testPlayStartsTheClockAndChoosingATimerDoesNot() {
        openTheBar()
        // Picking a timer while paused records the choice; it must not start the countdown.
        chooseTimer("5 minutes")
        XCTAssertFalse(
            clockValue().contains(":"),
            "choosing a timer while paused started the clock (saw \(clockValue()))")

        app.buttons["listenPause"].tap()
        let counting = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS ':'"), object: app.buttons["listenTimer"])
        XCTAssertEqual(
            XCTWaiter.wait(for: [counting], timeout: 8), .completed,
            "Play should start the clock, saw \(clockValue())")
        app.buttons["listenClose"].tap()
    }

    /// A timer chosen while paused replaces the time that was held. It used to keep the old one, so
    /// pausing with 10:00 left and choosing End of chapter still stopped after ten minutes.
    func testChangingTheTimerWhilePausedReplacesTheHeldTime() {
        openTheBar()
        chooseTimer("15 minutes")

        app.buttons["listenPause"].tap()
        let counting = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS ':'"), object: app.buttons["listenTimer"])
        XCTAssertEqual(
            XCTWaiter.wait(for: [counting], timeout: 8), .completed,
            "the clock should be running, saw \(clockValue())")

        // Pause with time on the clock, then change the choice.
        app.buttons["listenPause"].tap()
        chooseTimer("End of chapter")

        app.buttons["listenPause"].tap()
        let noClock = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (value CONTAINS ':')"), object: app.buttons["listenTimer"])
        XCTAssertEqual(
            XCTWaiter.wait(for: [noClock], timeout: 4), .completed,
            "End of chapter must leave no clock running, saw \(clockValue())")
        app.buttons["listenClose"].tap()
    }

    /// The Mac keeps the listening bar on screen whichever way the page is scrolled, and the phone
    /// used to hide it with the toolbar.
    func testTheListeningBarStaysVisibleWhileScrolling() {
        openTheBar()
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)
        let timer = app.buttons["listenTimer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 5), "the listening bar went with the toolbar")
        XCTAssertTrue(timer.isHittable, "the timer should still be tappable with the bars hidden")
        app.buttons["listenClose"].tap()
    }

    /// Pressing and holding a word opens the card that explains that word — not the verse it sits
    /// in, and not "No definition found" for a word John 1:1 certainly has an entry for.
    func testHoldingAWordOpensItsDefinition() {
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32)).press(forDuration: 1.2)
        XCTAssertTrue(
            app.descendants(matching: .any)["lookupCard"].waitForExistence(timeout: 6),
            "holding a word opened nothing")
        // The card draws the word in its own header, as the Mac does, not as a navigation title.
        let card = app.descendants(matching: .any)["lookupCard"]
        let words = [
            "In", "the", "beginning", "was", "Word", "and", "with", "God", "All", "things", "made",
            "him", "life", "light", "darkness", "same", "not", "any", "without",
        ]
        XCTAssertTrue(
            words.contains { card.staticTexts[$0].exists },
            "the card's title should be one word from the verse, not the whole verse")
        XCTAssertFalse(
            app.staticTexts["No definition found"].exists,
            "a word in John 1:1 should have an entry")
        app.buttons["lookupDone"].tap()
    }

    /// A word neither dictionary has says so plainly, and offers nothing to tap through to: there is
    /// no Wiktionary link, because the app never goes looking outside itself.
    func testAWordNotInTheDictionarySaysSo() {
        app.terminate()
        app.launchArguments = ["--uitest", "--lookup", "zzzqqq"]
        app.launch()
        XCTAssertTrue(app.staticTexts["No definition found"].waitForExistence(timeout: 10), "no card for the word")
        XCTAssertFalse(app.buttons["Wiktionary"].exists, "there should be no way out to the web")
    }

    /// The press must not get in the page's way: scrolling still works after a lookup, and the card
    /// closing leaves the reading and the page as they were.
    func testScrollingStillWorksAfterALookup() {
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["lookupCard"].waitForExistence(timeout: 6))
        app.buttons["lookupDone"].tap()
        let before = reference.label
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        XCTAssertNotEqual(before, reference.label, "the page would not scroll after a lookup")
    }

    /// The verse menu must never move the listening bar. It used to sit under it and push it up,
    /// which put the bar's stop button (✕) exactly where the menu's close button belongs — that is
    /// how a reading kept ending when a card opened.
    func testTheVerseMenuDoesNotMoveTheListeningBar() {
        openTheBar()
        app.buttons["listenPause"].tap()  // play
        let bar = app.buttons["listenPause"]
        let speaking = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == \"Pause reading\""), object: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 10), .completed, "the reading did not start")
        let before = bar.frame

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        XCTAssertTrue(
            app.buttons["selectionClose"].waitForExistence(timeout: 5), "no verse menu appeared")
        XCTAssertEqual(bar.frame, before, "the verse menu moved the listening bar")
        XCTAssertEqual(bar.label, "Pause reading", "the reading should still be playing")
    }

    /// The verse menu closes on its own button.
    func testTheVerseMenuCloses() {
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        XCTAssertTrue(app.buttons["selectionClose"].waitForExistence(timeout: 5), "no verse menu")
        app.buttons["selectionClose"].tap()
        XCTAssertFalse(
            app.buttons["selectionClose"].waitForExistence(timeout: 2), "the verse menu stayed open")
    }

    /// A note leaves the reading alone: it stops only when the reader stops it, as on the Mac.
    func testANoteLeavesTheReadingPlaying() {
        openTheBar()
        app.buttons["listenPause"].tap()  // play
        let bar = app.buttons["listenPause"]
        let speaking = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == \"Pause reading\""), object: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 10), .completed, "the reading did not start")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
        XCTAssertTrue(app.buttons["Note"].waitForExistence(timeout: 5), "no Note button")
        app.buttons["Note"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "the note editor did not open")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the bar went away")
        XCTAssertEqual(bar.label, "Pause reading", "opening a note stopped the reading")
    }

    /// A flick, then a drag straight after it, must not be refused.    /// A flick, then a drag straight after it, must not be refused.
    ///
    /// The reader is a UIScrollView and used to be the delegate of its own pan recogniser, so the
    /// check meant for the page tap also governed scrolling: a touch during a fling was refused, the
    /// scroll view was left dragging and decelerating with the pan at .possible, and every drag after
    /// that did nothing. Once wedged it stays wedged, so one refused touch is enough to fail.
    ///
    /// The reference label names the chapter only, so this runs in the Psalms, where a round of
    /// swipes is certain to cross a boundary — the page has to move on every single round.
    func testAFlickThenADragIsNotRefused() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("ps 23\n")
        expectChapter("Psalm 23")

        for round in 1...5 {
            let before = reference.label
            // No waiting between them: the later swipes land while the page is still coasting.
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            XCTAssertNotEqual(before, reference.label, "the page stopped answering drags on round \(round)")
        }
    }

    /// The baseline the reading test is measured against: an ordinary page scrolls.
    func testThePageScrollsWithNoReading() {
        let before = reference.label
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        XCTAssertNotEqual(before, reference.label, "the page would not scroll even with no reading running")
    }

    /// Mark's report: with a reading running, the page would not scroll while the voice kept going.
    /// Nothing about the reading is allowed to take the page away from the reader.
    func testThePageStillScrollsWhileReading() {
        app.buttons["listen"].tap()
        if app.buttons["chooseVoice"].waitForExistence(timeout: 4) {
            app.buttons["chooseVoice"].tap()
        }
        let pause = app.buttons["listenPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "the bar did not appear")
        // The bar opens paused, so start the reading: this test guards Mark's original report — the
        // page would not scroll while the voice was actually speaking.
        pause.tap()
        let speaking = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == \"Pause reading\""), object: pause)
        XCTAssertEqual(
            XCTWaiter.wait(for: [speaking], timeout: 10), .completed, "the reading did not start")

        let before = reference.label
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        XCTAssertNotEqual(before, reference.label, "the page would not scroll while a reading was running")
        // The bar stays for as long as the reading is open: only the toolbar hides for full-page text.
        XCTAssertTrue(pause.exists, "the listening bar went with the toolbar")
        app.buttons["listenClose"].tap()
    }

    func testScrollingDoesNotHitch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
        }
    }

    private func row(_ reference: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", reference)).firstMatch
    }

    /// John 3:16 is the most cross-referenced verse there is: the row must appear, the card must
    /// list the links, and tapping one must go there.
    /// The picker as the Mac has it: a chapter brings its verses up, and a verse is what goes there.
    func testPicksAVerseFromItsChapter() {
        app.buttons["reference"].tap()
        // One decision per page since the picker was split: the books come first, marked where you
        // are, then that book's chapters, then its verses.
        let john = bookRow("John")
        XCTAssertTrue(john.waitForExistence(timeout: 5), "John is not in the book list")
        john.tap()
        let chapterThree = app.buttons["John 3"].firstMatch
        XCTAssertTrue(chapterThree.waitForExistence(timeout: 5), "John offers no chapter 3")
        chapterThree.tap()
        let verseSixteen = app.buttons["John 3:16"].firstMatch
        XCTAssertTrue(verseSixteen.waitForExistence(timeout: 5), "John 3 shows no verses")
        verseSixteen.tap()
        expectChapter("John 3")
        XCTAssertTrue(verse("John 3:16").waitForExistence(timeout: 5))
    }

    /// The case that failed by hand: reading deep in the Old Testament, the picker has to open with
    /// the ticked book in view, or the reader has to go hunting for their own place.
    func testThePickerOpensOnTheBookBeingRead() {
        jump("mal 4")
        expectChapter("Malachi 4")
        app.buttons["reference"].tap()
        let malachi = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'book-' AND label BEGINSWITH 'Malachi,'")).firstMatch
        XCTAssertTrue(malachi.waitForExistence(timeout: 5), "Malachi is not in the book list")
        XCTAssertTrue(malachi.isHittable, "the ticked book was out of view when the picker opened")
    }

    /// A new reader is asked two questions once, and one tap with the defaults is enough.
    func testFirstLaunchAsksOnceAndStartsReading() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["--uitest", "--first-run"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Lamplit"].waitForExistence(timeout: 10),
            "a first launch shows no welcome"
        )
        XCTAssertTrue(app.buttons["Start reading"].exists, "there is no way out of the first launch")
        app.buttons["Start reading"].tap()
        XCTAssertTrue(reference.waitForExistence(timeout: 10), "the reader never opened")
        // And it is not asked again.
        app.terminate()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start reading"].exists, "the first launch came back")
    }

    /// About carries the licences, from the same list the Mac shows. A CC BY work with no credit is
    /// a licence breach, so this is not cosmetic.
    func testAboutCarriesTheLicences() {
        app.buttons["settings"].tap()
        let about = app.buttons["About and licences"].firstMatch
        // Settings opens at half height and About is the last section, so it starts below the fold.
        for _ in 0..<4 where !about.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(about.waitForExistence(timeout: 5), "Settings offers no way into About")
        about.tap()
        XCTAssertTrue(
            app.navigationBars["About"].waitForExistence(timeout: 5), "About did not open"
        )
        XCTAssertTrue(
            app.staticTexts["STEPBible"].waitForExistence(timeout: 5),
            "the STEPBible credit is missing"
        )
        // The sign-off is the last thing on the screen, so scroll to it. `matching` reads the
        // element's own label; `containing` looks at its descendants, which is a different question.
        let signoff = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Lamplit, by Mark Trent")
        ).firstMatch
        for _ in 0..<6 where !signoff.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(signoff.waitForExistence(timeout: 5), "the sign-off is missing")
    }

    /// Read Aloud on a fresh install: the button opens the panel, and the panel offers the one-time
    /// download rather than trying to speak without a voice.
    /// The first press of Listen asks whose voice, once, because hearing a voice is how that choice
    /// gets made. The voice ships in the app, so nothing is downloaded and nothing is missing.
    func testTheFirstListenAsksForAVoice() {
        app.terminate()
        app.launchArguments = ["--uitest", "--first-listen"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))

        app.buttons["listen"].tap()
        XCTAssertTrue(
            app.navigationBars["Choose a reading voice"].waitForExistence(timeout: 5),
            "the first Listen should ask which voice reads"
        )
        for row in ["Spencer", "Russell", "Freya", "Harper"] {
            XCTAssertTrue(
                app.buttons[row].waitForExistence(timeout: 3),
                "\(row) is not offered"
            )
        }
        XCTAssertFalse(
            app.buttons["Download the voice"].exists,
            "the voice ships in the app, so there is nothing to download"
        )
        app.buttons["chooseVoice"].tap()
        let play = app.buttons["listenPause"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "choosing a voice should open the bar")
        XCTAssertEqual(
            play.label, "Resume reading",
            "choosing a voice should open the bar paused, so nothing is said before Play")
    }

    /// A timer chosen while the reading is already running has to start then: the bar used to show
    /// the choice with no clock, because only starting a reading ever set the deadline.
    func testChoosingATimerWhileListeningStartsTheClock() {
        openTheBar()
        // The bar opens paused; a timer chosen once the reading is running starts from that moment.
        app.buttons["listenPause"].tap()
        let timer = app.buttons["listenTimer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10), "no listening bar to time")
        chooseTimer("5 minutes")

        let first = (timer.value as? String) ?? ""
        XCTAssertTrue(first.contains(":"), "the bar shows \"\(first)\" instead of a countdown")
        sleep(3)
        XCTAssertNotEqual((timer.value as? String) ?? "", first, "the countdown is not moving")

        // Paused, the clock waits with the voice: time spent not listening is not time spent on the
        // timer, which is how the Mac behaves.
        app.buttons["listenPause"].tap()
        sleep(3)
        let frozen = (timer.value as? String) ?? ""
        sleep(3)
        XCTAssertEqual((timer.value as? String) ?? "", frozen, "the clock kept running while paused")
        app.buttons["listenPause"].tap()
        sleep(2)
        XCTAssertNotEqual((timer.value as? String) ?? "", frozen, "the clock did not resume")
    }

    func testOpensRelatedVersesAndGoesThere() {
        jump("jn 3:16")
        expectChapter("John 3")
        let sixteen = verse("John 3:16")
        XCTAssertTrue(sixteen.waitForExistence(timeout: 3))
        sixteen.tap()
        let related = app.buttons["Related"]
        XCTAssertTrue(related.waitForExistence(timeout: 5), "no Related row on John 3:16")
        related.tap()
        XCTAssertTrue(
            app.navigationBars["Related to John 3:16"].waitForExistence(timeout: 5),
            "the card did not name the verse"
        )
        let link = app.buttons["Romans 5:8"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "John 3:16 does not offer Romans 5:8")
        link.tap()
        expectChapter("Romans 5")
        XCTAssertTrue(verse("Romans 5:8").waitForExistence(timeout: 5))
    }

    /// The verse in Greek, and the dictionary entry behind one of its words.
    func testReadsTheOriginalWordsAndTheirEntry() {
        jump("jn 3:16")
        expectChapter("John 3")
        let sixteen = verse("John 3:16")
        XCTAssertTrue(sixteen.waitForExistence(timeout: 3))
        sixteen.tap()
        let words = app.buttons["Words"]
        XCTAssertTrue(words.waitForExistence(timeout: 5), "no Words row on John 3:16")
        words.tap()
        XCTAssertTrue(
            app.navigationBars["Greek · John 3:16"].waitForExistence(timeout: 5),
            "the words sheet did not name the verse and its language"
        )
        let cells = app.cells
        XCTAssertTrue(cells.count >= 7, "John 3:16 listed \(cells.count) words")
        cells.element(boundBy: 0).tap()
        // The entry names itself by the Strong's number, beside its part of speech: "G2316 · noun".
        let numbered = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "G[0-9]{3,5}.*")
        ).firstMatch
        XCTAssertTrue(numbered.waitForExistence(timeout: 5), "no Greek number appeared after tapping a word")
    }

    /// The one way to reach the developer from inside the app (App Review 1.5). A phone with no Mail
    /// account cannot compose, so the row must say why and offer the address instead of doing nothing.
    func testSendFeedbackWithNoMailAccountOffersTheAddress() {
        app.buttons["settings"].tap()
        let row = app.buttons["sendFeedback"]
        // Settings opens at half height and this row sits under About, so it starts below the fold.
        for _ in 0..<4 where !row.exists {
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings offers no way to send feedback")
        row.tap()
        let alert = app.alerts["No email account on this iPhone"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "the row said nothing about the missing account")
        XCTAssertTrue(
            alert.buttons["Copy address"].exists, "the alert offers no way to get the address"
        )
        alert.buttons["OK"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: alert)
        wait(for: [gone], timeout: 5)
    }
}

extension XCUIApplication {
    /// A button in the selection bar, once the bar has slid into place (0.28 s): a tap while it
    /// moves lands on the text behind it.
    func selectionAction(_ label: String) -> XCUIElement {
        let button = buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 3), label)
        usleep(400_000)
        return button
    }

}
