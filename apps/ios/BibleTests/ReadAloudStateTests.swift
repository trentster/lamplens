import XCTest

/// The Read Aloud rules, without a phone, a voice or a sound: what Play, Pause, the timer menu, a
/// call and the bar's wording do. `ReadAloudState.swift` is compiled straight into this bundle, so
/// these run in a second with no app around them. Each rule names the Mac behaviour it matches.
final class ReadAloudStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func opened() -> ReadAloudState {
        var state = ReadAloudState()
        state.open()
        return state
    }

    private func playing(_ stop: ReadAloudStop) -> ReadAloudState {
        var state = opened()
        XCTAssertTrue(state.play(stop, at: t0))
        return state
    }

    // MARK: The clock

    func testAnIdleClockHasNoTime() {
        let clock = SleepClock()
        XCTAssertNil(clock.remaining(at: t0))
    }

    func testARunningClockCountsDown() {
        var clock = SleepClock()
        clock.run(for: 300, from: t0)
        XCTAssertEqual(clock.remaining(at: at(100)), 200)
        XCTAssertEqual(clock.remaining(at: at(400)), 0, "time left never goes below nothing")
    }

    func testAStoppedClockHoldsItsTimeHoweverLongItWaits() {
        var clock = SleepClock()
        clock.run(for: 300, from: t0)
        clock.stop(at: at(100))
        XCTAssertEqual(clock.remaining(at: at(5_000)), 200)
        clock.restart(from: at(5_000))
        XCTAssertEqual(clock.remaining(at: at(5_050)), 150)
    }

    func testRunningForNothingIsIdle() {
        var clock = SleepClock()
        clock.run(for: 300, from: t0)
        clock.run(for: nil, from: t0)
        XCTAssertEqual(clock.state, .idle)
    }

    // MARK: Opening and Play (the Mac's Reading::open and resume)

    func testTheBarOpensReadyWithNoClock() {
        let state = opened()
        XCTAssertEqual(state.phase, .ready)
        XCTAssertNil(state.clock.remaining(at: t0), "no clock may run before Play")
    }

    func testPlayFromReadyRunsTheFullTimer() {
        let state = playing(.fiveMinutes)
        XCTAssertEqual(state.phase, .reading)
        XCTAssertEqual(state.clock.remaining(at: at(60)), 240)
    }

    func testPlayWithEndOfChapterRunsNoClock() {
        let state = playing(.endOfChapter)
        XCTAssertEqual(state.phase, .reading)
        XCTAssertNil(state.clock.remaining(at: at(60)))
    }

    func testNothingPlaysWhenTheBarIsClosed() {
        var state = ReadAloudState()
        XCTAssertFalse(state.play(.fiveMinutes, at: t0))
        XCTAssertEqual(state.phase, .off)
    }

    // MARK: Pause

    func testPauseHoldsTheTimeLeftAndPlayCarriesOnFromIt() {
        var state = playing(.fifteenMinutes)
        XCTAssertTrue(state.pause(at: at(300)))
        XCTAssertEqual(state.phase, .paused)
        XCTAssertEqual(state.clock.remaining(at: at(3_000)), 600, "time paused is not time listened")
        XCTAssertTrue(state.play(.fifteenMinutes, at: at(3_000)))
        XCTAssertEqual(state.clock.remaining(at: at(3_060)), 540)
    }

    func testPauseBeforePlayDoesNothing() {
        var state = opened()
        XCTAssertFalse(state.pause(at: t0))
        XCTAssertEqual(state.phase, .ready)
    }

    func testPausingTwiceKeepsTheFirstHold() {
        var state = playing(.fiveMinutes)
        state.pause(at: at(60))
        XCTAssertFalse(state.pause(at: at(120)))
        XCTAssertEqual(state.clock.remaining(at: at(500)), 240)
    }

    // MARK: The timer menu (the Mac's Reading::choose)

    func testChoosingBeforePlayStartsNothing() {
        var state = opened()
        state.choose(.fiveMinutes, at: t0)
        XCTAssertNil(state.clock.remaining(at: t0))
        XCTAssertEqual(state.phase, .ready)
    }

    func testChoosingWhileReadingRunsFromNow() {
        var state = playing(.fiveMinutes)
        state.choose(.thirtyMinutes, at: at(120))
        XCTAssertEqual(state.clock.remaining(at: at(120)), 1_800)
    }

    func testChoosingEndOfChapterWhileReadingStopsTheClock() {
        var state = playing(.fiveMinutes)
        state.choose(.endOfChapter, at: at(60))
        XCTAssertNil(state.clock.remaining(at: at(60)))
    }

    func testChoosingWhilePausedReplacesTheHeldTime() {
        var state = playing(.fifteenMinutes)
        state.pause(at: at(300))
        state.choose(.thirtyMinutes, at: at(400))
        XCTAssertEqual(state.clock.remaining(at: at(900)), 1_800, "the new choice, in full, and still held")
        state.play(.thirtyMinutes, at: at(1_000))
        XCTAssertEqual(state.clock.remaining(at: at(1_100)), 1_700)
    }

    func testChoosingEndOfChapterWhilePausedLeavesNoClock() {
        var state = playing(.fifteenMinutes)
        state.pause(at: at(300))
        state.choose(.endOfChapter, at: at(400))
        state.play(.endOfChapter, at: at(500))
        XCTAssertNil(state.clock.remaining(at: at(600)), "Mark's report: it still stopped ten minutes later")
    }

    // MARK: Calls

    func testACallPausesAndMayResume() {
        var state = playing(.fifteenMinutes)
        XCTAssertTrue(state.pause(at: at(60), byInterruption: true))
        XCTAssertTrue(state.resumesAfterInterruption)
        XCTAssertEqual(state.clock.remaining(at: at(660)), 840, "a call does not eat the timer")
    }

    func testAPauseTheReaderChoseDoesNotResumeAfterACall() {
        var state = playing(.fifteenMinutes)
        state.pause(at: at(60))
        state.pause(at: at(70), byInterruption: true)
        XCTAssertFalse(state.resumesAfterInterruption, "the reader paused it, so it stays paused")
    }

    func testPlayingClearsTheCallFlag() {
        var state = playing(.fifteenMinutes)
        state.pause(at: at(60), byInterruption: true)
        state.play(.fifteenMinutes, at: at(120))
        XCTAssertFalse(state.resumesAfterInterruption)
    }

    // MARK: Failing and closing

    func testAFailureClearsTheClockAndCannotPlay() {
        var state = playing(.fiveMinutes)
        state.fail(.noVoice)
        XCTAssertEqual(state.phase, .failed(.noVoice))
        XCTAssertNil(state.clock.remaining(at: at(10)))
        XCTAssertFalse(state.play(.fiveMinutes, at: at(10)))
        XCTAssertTrue(state.phase.isOn, "the bar stays to say what went wrong")
    }

    func testClosingTurnsEverythingOff() {
        var state = playing(.fiveMinutes)
        state.close()
        XCTAssertEqual(state.phase, .off)
        XCTAssertFalse(state.phase.isOn)
        XCTAssertNil(state.clock.remaining(at: at(10)))
    }

    func testReopeningStartsReadyAgain() {
        var state = playing(.fiveMinutes)
        state.close()
        state.open()
        XCTAssertEqual(state.phase, .ready)
        XCTAssertNil(state.clock.remaining(at: at(10)))
    }

    // MARK: What the bar says (the Mac's listening_text)

    func testTheBarSaysReadyBeforeAnythingIsSaid() {
        XCTAssertEqual(opened().status(hasSpoken: false), "Ready")
    }

    func testTheBarSaysListeningWhilePlaying() {
        XCTAssertEqual(playing(.endOfChapter).status(hasSpoken: false), "Listening")
    }

    func testTheBarSaysPausedOnlyOnceSomethingHasBeenSaid() {
        var state = playing(.endOfChapter)
        state.pause(at: at(1))
        XCTAssertEqual(state.status(hasSpoken: false), "Ready")
        XCTAssertEqual(state.status(hasSpoken: true), "Paused")
    }

    func testAFailureIsSaidInPlainWords() {
        var state = opened()
        state.fail(.nothingToRead)
        XCTAssertEqual(state.status(hasSpoken: false), "Nothing here to read")
    }

    // MARK: The end of a chapter

    /// Keep reading walks into the next chapter whatever the clock says: it has no clock.
    func testKeepReadingAlwaysCarriesOn() {
        XCTAssertTrue(ReadAloudStop.keepReading.carriesOn(timeLeft: nil))
        XCTAssertTrue(ReadAloudStop.keepReading.carriesOn(timeLeft: 0))
    }

    /// End of chapter means exactly that, even if a clock somehow had time on it.
    func testEndOfChapterNeverCarriesOn() {
        XCTAssertFalse(ReadAloudStop.endOfChapter.carriesOn(timeLeft: nil))
        XCTAssertFalse(ReadAloudStop.endOfChapter.carriesOn(timeLeft: 600))
    }

    /// A timer is a sleep timer, not a cap: with four minutes left when Matthew 16 ends, the reading
    /// goes on into Matthew 17. Only a clock that has run out, or none at all, stops it. The Mac's
    /// `carry_on`.
    func testATimerCarriesOnWhileItHasTimeLeft() {
        let timers = ReadAloudStop.allCases.filter { $0.seconds != nil }
        XCTAssertEqual(timers.count, 6)
        for stop in timers {
            XCTAssertTrue(stop.carriesOn(timeLeft: 240), "\(stop) with time left")
            XCTAssertFalse(stop.carriesOn(timeLeft: 0), "\(stop) with its time up")
            XCTAssertFalse(stop.carriesOn(timeLeft: nil), "\(stop) with no clock")
        }
    }

    /// The rule reads the same clock the bar shows: a timer chosen and played with five minutes
    /// still has time to carry on when a short chapter ends a minute in.
    func testAPlayingTimerStillHasTimeAtAShortChaptersEnd() {
        let state = playing(.fiveMinutes)
        XCTAssertTrue(ReadAloudStop.fiveMinutes.carriesOn(timeLeft: state.clock.remaining(at: at(60))))
        XCTAssertFalse(ReadAloudStop.fiveMinutes.carriesOn(timeLeft: state.clock.remaining(at: at(300))))
    }

    // MARK: The timer menu's rows

    func testTheMenuHasTheMacsEightRowsInOrder() {
        XCTAssertEqual(
            ReadAloudStop.allCases.map(\.title),
            ["End of chapter", "5 minutes", "15 minutes", "30 minutes", "45 minutes", "1 hour",
             "2 hours", "Keep reading"])
        XCTAssertNil(ReadAloudStop.endOfChapter.seconds)
        XCTAssertNil(ReadAloudStop.keepReading.seconds)
        XCTAssertEqual(ReadAloudStop.twoHours.seconds, 7_200)
    }

    /// The UI tests and the saved choice both use these names; renaming one would lose a reader's
    /// remembered timer.
    func testTheSavedNamesDoNotChange() {
        XCTAssertEqual(
            ReadAloudStop.allCases.map(\.rawValue),
            ["endOfChapter", "fiveMinutes", "fifteenMinutes", "thirtyMinutes", "fortyFiveMinutes",
             "sixtyMinutes", "twoHours", "keepReading"])
    }
}
