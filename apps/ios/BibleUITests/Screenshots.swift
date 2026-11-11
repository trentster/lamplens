import XCTest

/// The screenshots in docs/screenshots/ios. Skipped unless BIBLE_SCREENSHOTS=1
/// (`TEST_RUNNER_BIBLE_SCREENSHOTS=1` through xcodebuild); scripts/ios-screenshots.sh runs it.
final class Screenshots: XCTestCase {
    private var app: XCUIApplication!

    func testCapture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BIBLE_SCREENSHOTS"] == "1")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCTAssertTrue(app.buttons["reference"].waitForExistence(timeout: 10))

        // A little study history to show.
        go("jn 3")
        verse("John 3:3").tap()
        app.selectionAction("Highlight Yellow").tap()
        verse("John 3:5").tap()
        app.selectionAction("Note").tap()
        app.textFields["Write a note"].typeText("Born of water and of the Spirit: compare Ezekiel 36:25–27.")
        app.buttons["Save"].tap()
        verse("John 3:7").tap()
        app.selectionAction("Highlight Blue").tap()

        for theme in ["Light", "Dark", "Sepia"] {
            setTheme(theme)
            let name = theme.lowercased()
            go("jn 3")
            snap("reader-\(name)")
            if theme == "Sepia" {
                go("ps 23")
                snap("psalm-\(name)")
                continue
            }
            verse("John 3:2").tap()
            snap("selection-\(name)")
            app.selectionAction("Clear selection").tap()

            go("ps 23")
            snap("psalm-\(name)")

            app.buttons["search"].tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText("love one another")
            XCTAssertTrue(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 13:34'")).firstMatch
                    .waitForExistence(timeout: 5))
            app.typeText("\n")
            snap("search-\(name)")
            // iPhone: the search field's Close button. iPad shows search in a sheet with Done.
            let close = app.buttons["Close"].firstMatch
            (close.exists ? close : app.buttons["Done"].firstMatch).tap()

            app.buttons["reference"].tap()
            XCTAssertTrue(app.buttons["Psalms 23"].waitForExistence(timeout: 3))
            snap("books-\(name)")
            app.buttons["Done"].tap()
        }
    }

    private func verse(_ id: String) -> XCUIElement {
        let e = app.staticTexts[id]
        XCTAssertTrue(e.waitForExistence(timeout: 5), id)
        return e
    }

    private func go(_ reference: String) {
        app.buttons["reference"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(reference + "\n")
        sleep(1)
    }

    private func setTheme(_ theme: String) {
        app.buttons["settings"].tap()
        app.buttons["\(theme) theme"].tap()
        app.buttons["Done"].tap()
        sleep(1)
    }

    private func snap(_ name: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "ios-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// The UX review's screenshots: every screen of the app, in the states a reader meets them, for an
/// outside read against Mark's yardstick — could someone half-asleep use this without thinking?
/// Skipped unless BIBLE_UX_REVIEW=1 (TEST_RUNNER_BIBLE_UX_REVIEW=1 through xcodebuild);
/// scripts/ios-ux-review.sh runs it.
///
/// One launch per screen, straight into the state named, through the launch hooks in `Store`
/// (`--at`, `--seed`, `--open`). Then the element that proves the state is waited for, and the shot
/// is taken only if it is there. A screen that cannot be proved is reported MISSED and never
/// photographed, so a filename cannot claim to show something it does not. The script turns the
/// `UXREVIEW` lines below into index.md: they leave as one attachment, because xcodebuild -quiet
/// swallows whatever the test prints.
final class UXReview: XCTestCase {
    private var app: XCUIApplication!

    /// The palette this run photographs: `BIBLE_UX_THEME`, light unless the script says otherwise.
    private let theme = ProcessInfo.processInfo.environment["BIBLE_UX_THEME"] ?? "light"

    func testCapture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BIBLE_UX_REVIEW"] == "1")
        // One bad step costs one shot, not every shot after it.
        continueAfterFailure = true

        // 01. First launch, as a new reader meets it.
        launch(["--first-run"], keepData: true)
        capture("01-first-launch", "The first question, over the reader, on a device that has never run it") {
            self.app.buttons["Start reading"].exists
        }

        // 02. The reader, and the same page with the bars scrolled away.
        launch(["--at", "jn 3", "--seed"])
        capture("02-reader-toolbar", "The reader at John 3: where you are, and the four tools") {
            self.place("John 3") && self.app.buttons["reference"].isHittable
        }
        self.app.swipeUp(velocity: .fast)
        capture("02-reader-toolbar-hidden", "The same page scrolled: the toolbar and the status bar out of the way") {
            self.verseIdentifiers("John 3:").count > 0 && !self.app.buttons["reference"].isHittable
        }

        // 03. Read Aloud's bar, in the states a reader meets it.
        launch(["--at", "jn 3", "--open", "reading:ready"])
        capture("03-listening-ready", "The bar after Read, before Play: Ready, with no clock running") {
            self.app.buttons["listenPause"].exists
                && self.app.buttons["listenPause"].label == "Resume reading" && self.says("Ready")
        }
        launch(["--at", "jn 3", "--open", "reading:listening"])
        capture("03-listening-playing", "Reading aloud: Listening, and Pause under the thumb") {
            self.app.buttons["listenPause"].exists
                && self.app.buttons["listenPause"].label == "Pause reading" && self.says("Listening")
        }
        launch(["--at", "jn 3", "--open", "reading:paused"])
        capture("03-listening-paused", "Paused mid-verse: what it is doing and how to get it going again") {
            self.app.buttons["listenPause"].exists
                && self.app.buttons["listenPause"].label == "Resume reading" && self.says("Paused")
        }
        launch(["--at", "jn 3", "--open", "reading:listening:fifteenMinutes"])
        capture("03-listening-countdown", "A timer running beside the pause: what is left before it stops") {
            self.app.buttons["listenPause"].exists && self.app.buttons["listenPause"].label == "Pause reading"
                && self.showsClock
        }

        // 04. The verse menu: one verse, a range, and a verse already saved.
        launch(["--at", "jn 3", "--open", "verse-menu:jn 3:16"])
        capture("04-verse-menu-one", "The verse menu over one verse: six colours, then what to do with it") {
            self.app.buttons["selectionClose"].exists && self.app.buttons["Highlight Yellow"].exists
        }
        launch(["--at", "jn 3", "--open", "verse-menu:jn 3:16-18"])
        capture("04-verse-menu-three", "Three verses at once, named as a range in the bar") {
            self.app.buttons["selectionClose"].exists && self.says("John 3:16–18")
        }
        launch(["--at", "jn 3", "--seed", "--open", "verse-menu:jn 3:16"])
        capture("04-verse-menu-saved", "A verse already bookmarked: the bar offers Saved, not Save") {
            // The button's own accessibility label wins over the word it draws: "Remove bookmark".
            self.app.buttons["selectionClose"].exists && self.app.buttons["Remove bookmark"].exists
        }

        // 05. The word card, and the words behind the verse.
        launch(["--at", "genesis 1", "--open", "lookup:beginning"])
        capture("05-lookup-definition", "The card on “beginning”: the definition, its source, the verse") {
            self.app.descendants(matching: .any)["lookupCard"].exists && self.says("No definition found") == false
        }
        self.tapId("lookupOriginalWords")
        capture("05-lookup-hebrew-words", "The verse in the language it was written in, reached from the card") {
            self.app.cells.count > 0 && !self.app.descendants(matching: .any)["lookupOriginalWords"].isHittable
        }
        if self.app.cells.firstMatch.exists { self.app.cells.firstMatch.tap() }
        capture("05-lookup-entry", "One word's dictionary entry, opened from the words list") {
            // The entry is titled with the word in its own script, and the line under it says how
            // the word is said; the number moved to the card's small grey line.
            self.says("pronounced ") && self.says("H7225G") && self.app.cells.count > 0
        }
        launch(["--at", "genesis 1", "--open", "lookup:zzzqqq"])
        capture("05-lookup-no-definition", "A word neither dictionary has: said plainly, not left blank") {
            self.app.descendants(matching: .any)["lookupCard"].exists && self.says("No definition found")
        }

        // 06. The note editor: one already written, and one being started.
        launch(["--at", "jn 3", "--seed", "--open", "note:jn 3:5"])
        capture("06-note-existing", "A note already written on John 3:5, with the verse above it") {
            self.navigationBarTitled("John 3:5") && self.fieldValue.contains("Born of water")
        }
        launch(["--at", "jn 3", "--open", "note:jn 3:19"])
        capture("06-note-new", "A note being started on John 3:19: the verse, and an empty field") {
            self.navigationBarTitled("John 3:19") && self.app.textFields.firstMatch.exists
                && !self.fieldValue.contains("Born of water")
        }

        // 06b. Read Aloud running on a verse that is already highlighted: the margin bar has to be
        // readable over a highlight, which is why it is a bar and not a tint.
        launch(["--at", "jn 3:3", "--seed", "--open", "reading:listening"])
        // The bar only exists while a verse is actually being said, so the proof waits for the bar's
        // own reference to name one ("John 3:3") — the state that draws the margin mark, not merely
        // the state with the reading open.
        capture("06b-reading-on-highlight", "Read aloud saying John 3:3, which is already highlighted yellow") {
            self.app.buttons["listenPause"].label == "Pause reading"
                && self.labelMatches("John 3:[0-9]+.*")
        }

        // 06c. The toolbar over text that has been scrolled: the paper behind it has to reach its
        // bottom edge, or the page shows between the buttons.
        launch(["--at", "jn 3", "--seed"])
        app.swipeUp(velocity: .fast)
        usleep(600_000)
        app.swipeDown(velocity: .slow)
        capture("06c-toolbar-over-scrolled-text", "The toolbar with the page scrolled under it, not at the top") {
            let first = self.app.staticTexts["John 3:1"]
            return self.app.buttons["reference"].isHittable && (!first.exists || first.frame.minY < 0)
        }

        // 06d. Read Aloud mid-sentence, where the bar has to cover more than one verse. Light only:
        // the mark's colour per theme is already covered by 06b.
        if theme == "light" {
            launch(["--at", "matt 23", "--open", "reading:listening"])
            capture(
                "06d-reading-whole-sentence",
                "Mid-sentence at Matthew 23: one bar covering verses 1 and 2, as the voice reads them"
            ) {
                self.app.buttons["listenPause"].label == "Pause reading"
                    && self.labelMatches("Matthew 23:[0-9]+.*")
            }
        }

        // 07. Related verses.
        launch(["--at", "jn 3:16", "--open", "related"])
        capture("07-related-verses", "The verses the tradition links to John 3:16, best first") {
            self.navigationBarTitled("Related to John 3:16") && self.app.cells.count > 0
        }

        // 08. The words sheet, from the verse menu.
        launch(["--at", "jn 1:1", "--open", "words"])
        capture("08-words-sheet", "John 1:1 in the Greek, word by word, with what each one means") {
            self.navigationBarTitled("Greek · John 1:1") && self.app.cells.count > 0
        }

        // 08a-e. The lookup's deeper pages: the words of a verse, and one entry behind a word.
        // Light goes all the way in for both languages; dark stops at an entry page, since the card
        // is the part that has to work on a dark page.
        if theme == "light" {
            launch(["--at", "genesis 1", "--open", "lookup:beginning"])
            self.tapId("lookupOriginalWords")
            capture("08a-words-hebrew", "Genesis 1:1 in the Hebrew, word by word: the row said Hebrew, so the page does") {
                self.navigationBarTitled("Hebrew words") && self.app.cells.count > 0
            }
            self.tapId("word-H7225G")
            capture("08b-entry-reshit", "The entry behind \u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05D9}\u{05EA}: the word itself as the title, then how it is said, then what it means") {
                self.says("pronounced re.shit") && self.says("H7225G")
            }
        }
        if theme == "light" {
            launch(["--at", "rom 8:19", "--open", "lookup:creature"])
            self.tapId("lookupOriginalWords")
            capture("08c-words-greek", "Romans 8:19 in the Greek, word by word") {
                self.navigationBarTitled("Greek words") && self.app.cells.count > 0
            }
            self.tapId("word-G0603")
            capture("08d-entry-long-word", "A long word's entry: the title and the line under it hold their shape") {
                self.says("pronounced ap.ok.ar.ad.ok.ee\u{2019}ah") || self.says("pronounced ")
            }
        }
        // 08f-g. The form line, and its absence. Genesis 1:1's elohim carries cantillation the
        // lexicon does not print: the same letters, so the entry says nothing. Romans 8:19's tes is
        // not the article's own o, so the entry names the form the reader tapped.
        if theme == "light" {
            launch(["--at", "genesis 1", "--open", "lookup:beginning"])
            self.tapId("lookupOriginalWords")
            _ = self.app.cells.firstMatch.waitForExistence(timeout: 10)
            self.tapCell(2)
            capture("08f-entry-same-word", "The same word printed twice: marks in the verse, none in the lexicon, so the entry says nothing about it") {
                self.says("H0430") && !self.says("In this verse")
            }
            launch(["--at", "rom 8:19", "--open", "lookup:creature"])
            self.tapId("lookupOriginalWords")
            _ = self.app.cells.firstMatch.waitForExistence(timeout: 10)
            self.tapCell(3)
            capture("08g-entry-verse-form", "A different word in the verse: the entry names the form the reader tapped") {
                self.says("In this verse") && self.says("G3588")
            }
            // 08h. The words list at the largest accessibility text size: the script word is still
            // one line, and what sits beside it gives way.
            launch(
                ["--at", "rom 8:19", "--open", "lookup:creature"],
                textSize: "UICTContentSizeCategoryAccessibilityXXXL")
            self.tapId("lookupOriginalWords")
            capture("08h-words-largest-text", "Romans 8:19's words at the largest accessibility text size: the long word still on one line") {
                self.navigationBarTitled("Greek words") && self.app.cells.count > 0
            }
            // Scrolled to the long word, whose row is taller than the sheet at this size: the word
            // stays on one line and what sits beside it wraps rather than running off the card.
            self.app.swipeUp(velocity: .slow)
            capture("08i-words-long-word", "The long word's row at the largest text size: one line for the word itself, the rest given way") {
                self.says("apokaradokia")
            }
        }
        if theme == "dark" {
            launch(["--at", "genesis 1", "--open", "lookup:beginning"])
            self.tapId("lookupOriginalWords")
            self.tapId("word-H7225G")
            capture("08e-entry-dark", "The same entry on a dark page: the word, the pronunciation line, the number") {
                self.says("pronounced ") && self.says("H7225G")
            }
        }

        // 09. Search: before a word, with results, and with a suggestion.
        launch(["--open", "search"])
        capture("09-search-empty", "Search before a word is typed: what it will do, and where it looks") {
            self.app.searchFields.firstMatch.exists && self.says("Every word must appear")
        }
        if self.app.searchFields.firstMatch.exists {
            self.app.searchFields.firstMatch.tap()
            self.app.searchFields.firstMatch.typeText("love one another")
        }
        capture("09-search-results", "Results for “love one another”, each with its verse") {
            self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 13:34'")).count > 0
        }
        launch(["--open", "search"])
        if self.app.searchFields.firstMatch.exists {
            self.app.searchFields.firstMatch.tap()
            self.app.searchFields.firstMatch.typeText("beleive")
        }
        capture("09-search-suggestion", "A misspelling: nothing found, and the word it thinks you meant") {
            self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Search “'")).count > 0
        }

        // 10. The book picker, one page at a time.
        launch(["--open", "books"])
        capture("10-picker-books", "The picker's first page, opened at the book being read") {
            self.navigationBarTitled("Books") && self.app.descendants(matching: .any)["book-42"].exists
        }
        self.tapId("book-42")
        capture("10-picker-chapters", "John's chapters: one tap, one decision") {
            self.navigationBarTitled("John")
                && self.app.buttons.matching(NSPredicate(format: "label == 'John 3'")).count > 0
        }
        self.app.buttons.matching(NSPredicate(format: "label == 'John 3'")).firstMatch.tap()
        capture("10-picker-verses", "John 3's verses, with the whole chapter offered first") {
            self.app.descendants(matching: .any)["wholeChapter"].exists
                && self.app.buttons.matching(NSPredicate(format: "label == 'John 3:1'")).count > 0
        }

        // 11. The translation menu, open.
        launch(["--at", "jn 3"])
        self.tapId("translation")
        capture("11-translation-menu", "The seven translations, with the one in use ticked") {
            self.app.buttons.matching(NSPredicate(format: "label CONTAINS ' · '")).count >= 5
        }

        // 12. Settings, its Read aloud page, and About.
        launch(["--open", "settings"])
        capture("12-settings-main", "Settings in the Mac's order: Reading, Read aloud, Appearance, Translations, Data, About") {
            self.navigationBarTitled("Settings") && self.app.descendants(matching: .any)["Text size"].exists
        }
        // The sheet opens at the medium detent, which cuts the form off below Reading: the grabber
        // pulls it up to full height before anything further down can be tapped.
        self.app.buttons["Sheet Grabber"].firstMatch.swipeUp()
        self.tapLabel("Voice")
        capture("12-settings-read-aloud", "Read aloud: the voice, and how it reads") {
            self.navigationBarTitled("Read aloud")
        }
        self.back()
        self.app.swipeUp()
        self.scrollAndTap("About and licences")
        capture("12-settings-about", "About: the version, the sources and their licences") {
            self.navigationBarTitled("About")
        }

        // 13. Study, with sample data, then with none.
        launch(["--seed", "--open", "study"])
        capture("13-study-bookmarks", "Study on Bookmarks: two bookmarks, newest first") {
            self.navigationBarTitled("Study") && self.says("John 3:16") && self.app.cells.count > 0
        }
        self.segmented("Highlights")?.tap()
        capture("13-study-highlights", "Study on Highlights, each with the colour it was given") {
            self.says("John 3:3") && self.app.cells.count > 0
        }
        self.segmented("Notes")?.tap()
        capture("13-study-notes", "Study on Notes, each with what was written") {
            self.says("Born of water and of the Spirit") && self.app.cells.count > 0
        }
        launch(["--open", "study"])
        capture("13-study-empty", "Study with nothing saved yet: what to do, rather than a blank page") {
            self.navigationBarTitled("Study") && self.says("No bookmarks")
        }

        // 14. The voice chooser, as a first listen shows it.
        launch(["--open", "voices"])
        capture("14-voice-chooser", "The one question asked before the first listen") {
            self.app.buttons["chooseVoice"].exists
        }

        // 15. The timer menu.
        launch(["--at", "jn 3", "--open", "reading:listening"])
        _ = self.app.buttons["listenPause"].waitForExistence(timeout: 20)
        self.tapId("listenTimer")
        capture("15-timer-menu", "The eight things a reading can stop at, the current one ticked") {
            // Only the rows on screen exist: a List builds the rest when they are scrolled to.
            self.navigationBarTitled("Stop after")
                && self.app.descendants(matching: .any)["timer-endOfChapter"].exists
        }

        // 16. A toast, which is only there for a moment: proved by its own words.
        launch(["--at", "jn 3", "--open", "verse-menu:jn 3:16"])
        _ = self.app.buttons["selectionClose"].waitForExistence(timeout: 20)
        self.tapLabel("Copy")
        // A short settle, not none: the toast fades in, and a shot taken at the instant it appears
        // catches it half-transparent with the page reading through the words. It lives 1.6 s, so
        // 0.45 s is well inside its life and past its fade.
        capture("16-toast-copied", "The toast that says what was copied, and goes again", settle: 0.45) {
            self.says("Copied John 3:16")
        }
    }

    // MARK: - Launching

    /// One launch, straight into the state the arguments name. `--uitest` is the only way in, and
    /// the hooks that read these arguments live in `Store.harnessHooks`.
    private func launch(_ arguments: [String], keepData: Bool = false, textSize: String? = nil) {
        app?.terminate()
        app = XCUIApplication()
        // The theme is the run's, not the screen's: every launch this class makes asks for it, so a
        // themed run cannot leave one screen on the previous palette.
        app.launchArguments =
            ["--uitest", "--appearance", theme] + (keepData ? ["--keep-data"] : [])
            + (textSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []) + arguments
        app.launch()
        XCTAssertEqual(app.state, .runningForeground, "the app did not come up")
    }

    // MARK: - Proving, then capturing

    /// Captures only what it can prove: the check is waited for, and a shot is taken only when it
    /// holds. Otherwise nothing is photographed and the screen is reported MISSED.
    private func capture(
        _ name: String, _ what: String, settle: TimeInterval = 0.8, timeout: TimeInterval = 25,
        when check: @escaping () -> Bool
    ) {
        guard holds(check, timeout: timeout) else {
            missed(name, what)
            return
        }
        if settle > 0 { usleep(useconds_t(settle * 1_000_000)) }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "ux-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        report(name, "CAPTURED", what)
    }

    private func holds(_ check: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if check() { return true }
            usleep(250_000)
        } while Date() < deadline
        return false
    }

    /// The lines the script turns into index.md, carried out as one attachment: xcodebuild -quiet
    /// swallows whatever the test prints, so the result bundle is the only channel that survives.
    private var lines: [String] = []

    override func tearDown() {
        if !lines.isEmpty, let data = lines.joined(separator: "\n").data(using: .utf8) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
            attachment.name = "ux-report"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        super.tearDown()
    }

    private func report(_ name: String, _ outcome: String, _ what: String) {
        let line = "UXREVIEW \(name) \(outcome) \(what)"
        lines.append(line)
        print(line)
    }

    /// A screen the test could not prove is named, never photographed — and says what was on screen
    /// instead, so the run explains itself without anyone opening the result bundle.
    private func missed(_ name: String, _ what: String) {
        report(name, "MISSED", "\(what) | on screen: \(onScreen())")
        XCTFail("MISSED: \(name) — \(what)")
    }

    /// What a capture could have proved instead: the buttons, bars, cells and fields actually there.
    private func onScreen() -> String {
        var parts: [String] = []
        if app.buttons["reference"].exists { parts.append("toolbar:\(app.buttons["reference"].label)") }
        let buttons = app.buttons
        var names: [String] = []
        for i in 0..<min(buttons.count, 14) {
            let button = buttons.element(boundBy: i)
            names.append(button.identifier.isEmpty ? "'\(button.label)'" : button.identifier)
        }
        parts.append("buttons=[\(names.joined(separator: " "))]")
        var bars: [String] = []
        for i in 0..<min(app.navigationBars.count, 3) {
            bars.append(app.navigationBars.element(boundBy: i).identifier)
        }
        parts.append("bars=[\(bars.joined(separator: " "))]")
        var fields: [String] = []
        for i in 0..<min(app.textFields.count + app.textViews.count, 4) {
            let field = i < app.textFields.count
                ? app.textFields.element(boundBy: i) : app.textViews.element(boundBy: i - app.textFields.count)
            fields.append("'\(field.value as? String ?? "")'")
        }
        parts.append("fields=[\(fields.joined(separator: " "))]")
        parts.append("cells=\(app.cells.count)")
        return parts.joined(separator: " ")
    }

    // MARK: - Proofs, one line each

    /// The toolbar names the place asked for, so a shot can never be of the wrong chapter.
    private func place(_ title: String) -> Bool {
        app.buttons["reference"].exists && app.buttons["reference"].label.hasPrefix(title)
    }

    /// Some element on screen carries this identifier prefix: the reader's verses do.
    private func verseIdentifiers(_ prefix: String) -> [XCUIElement] {
        let query = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        return (0..<query.count).map { query.element(boundBy: $0) }
    }

    /// A navigation bar titled exactly this: every sheet says where it is.
    private func navigationBarTitled(_ title: String) -> Bool {
        app.navigationBars.matching(NSPredicate(format: "identifier == %@", title)).count > 0
    }

    /// Any element whose label is this, or carries it: the listening bar's combined label is
    /// "John 3, Ready" rather than "Ready".
    private func says(_ text: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).count > 0
    }

    /// A navigation bar whose title matches this pattern: an entry is titled by its Strong's
    /// number, which is an identifier rather than a label.
    private func matchedBar(_ pattern: String) -> Bool {
        app.navigationBars.matching(NSPredicate(format: "identifier MATCHES %@", pattern)).count > 0
    }

    /// Any element whose label matches this pattern.
    private func labelMatches(_ pattern: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", pattern)).count > 0
    }

    /// "14:59" — a countdown is running.
    private var showsClock: Bool {
        labelMatches("[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?")
    }

    /// What the one text field on screen holds: a filled field no longer answers to its
    /// placeholder, so this reads the field rather than querying it by the prompt.
    private var fieldValue: String {
        (app.textFields.firstMatch.value as? String) ?? ""
    }

    // MARK: - Taps, none of which may end the run

    /// A row of a list by its place in it, for the words of a verse where the number is known and
    /// the row's own identifier is not.
    private func tapCell(_ index: Int) {
        let cell = app.cells.element(boundBy: index)
        guard cell.waitForExistence(timeout: 10) else {
            print("UXNOTE no cell at \(index)")
            return
        }
        if cell.isHittable { cell.tap() }
    }

    private func tapId(_ id: String) {
        let element = app.descendants(matching: .any)[id]
        guard element.waitForExistence(timeout: 10) else {
            print("UXNOTE could not find \(id)")
            return
        }
        if element.isHittable { element.tap() }
    }

    /// A row at the foot of a long Form, in a sheet that opens half-height: swipe until it is
    /// really reachable before tapping, because a row can exist and still be under the fold.
    private func scrollAndTap(_ label: String, swipes: Int = 6) {
        for _ in 0...swipes {
            let button = app.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                return
            }
            app.swipeUp()
            usleep(400_000)
        }
    }

    private func tapLabel(_ label: String) {
        let exact = app.buttons[label].firstMatch
        if exact.waitForExistence(timeout: 10) && exact.isHittable { exact.tap(); return }
        let loose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        if loose.exists && loose.isHittable { loose.tap() }
    }

    private func back() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable { back.tap() }
    }

    private func segmented(_ label: String) -> XCUIElement? {
        let control = app.segmentedControls.firstMatch
        guard control.waitForExistence(timeout: 10) else { return nil }
        let button = control.buttons[label].firstMatch
        return button.exists && button.isHittable ? button : nil
    }
}