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
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
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
        XCTAssertTrue(app.buttons["listenPause"].waitForExistence(timeout: 15), "the reading did not start")
        let before = reference.label
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        XCTAssertNotEqual(before, reference.label, "the page would not scroll while a reading was running")
        // Turning the page stops the reading; the bar goes with it.
        XCTAssertFalse(app.buttons["listenPause"].exists, "the reading should have stopped when the page turned")
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
        // The picker opens with the book you are reading already expanded (John 1 on a fresh
        // launch), so its chapters are already on screen.
        let chapterThree = app.buttons["John 3"].firstMatch
        XCTAssertTrue(chapterThree.waitForExistence(timeout: 5))
        chapterThree.tap()
        let verseSixteen = app.buttons["John 3:16"].firstMatch
        XCTAssertTrue(verseSixteen.waitForExistence(timeout: 5), "John 3 shows no verses")
        verseSixteen.tap()
        expectChapter("John 3")
        XCTAssertTrue(verse("John 3:16").waitForExistence(timeout: 5))
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
        XCTAssertTrue(
            app.buttons["listenPause"].waitForExistence(timeout: 10),
            "choosing a voice should start reading"
        )
    }

    /// A timer chosen while the reading is already running has to start then: the bar used to show
    /// the choice with no clock, because only starting a reading ever set the deadline.
    func testChoosingATimerWhileListeningStartsTheClock() {
        app.buttons["listen"].tap()
        if app.buttons["chooseVoice"].waitForExistence(timeout: 3) {
            app.buttons["chooseVoice"].tap()
        }
        let timer = app.buttons["listenTimer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 10), "no listening bar to time")
        timer.tap()
        let five = app.buttons["timer-fiveMinutes"]
        XCTAssertTrue(five.waitForExistence(timeout: 5), "the timer rows are not offered")
        five.tap()

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
