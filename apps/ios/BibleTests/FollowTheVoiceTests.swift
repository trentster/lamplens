import XCTest

/// The page following the voice: when it moves, and where the verse lands. The same cases as the
/// Mac's `follow_tests` in `crates/app/src/reader/mod.rs`, so the two apps follow alike.
final class FollowTheVoiceTests: XCTestCase {
    private let toolbar: CGFloat = 52
    private let viewport: CGFloat = 852

    private var landing: CGFloat { toolbar + (viewport - toolbar) * FollowTheVoice.landing }

    func testAVerseInTheComfortablePartOfTheScreenIsLeftAlone() {
        XCTAssertNil(FollowTheVoice.move(top: 300, height: 90, toolbar: toolbar, viewport: viewport))
        XCTAssertNil(
            FollowTheVoice.move(top: toolbar, height: 90, toolbar: toolbar, viewport: viewport),
            "just under the toolbar is fine")
    }

    func testAVerseNearTheFootOfThePageIsBroughtUpToTheLandingLine() {
        let top = toolbar + (viewport - toolbar) * FollowTheVoice.trigger - 10
        let move = FollowTheVoice.move(top: top, height: 90, toolbar: toolbar, viewport: viewport)
        XCTAssertNotNil(move, "it should move")
        XCTAssertGreaterThan(move ?? 0, 0, "the text moves up")
        XCTAssertEqual(top - (move ?? 0), landing, accuracy: 0.01, "and lands a third from the top")
    }

    func testAVerseAboveTheTopOfThePageComesBackDown() {
        let top = toolbar - 200
        let move = FollowTheVoice.move(top: top, height: 90, toolbar: toolbar, viewport: viewport)
        XCTAssertNotNil(move, "it should move")
        XCTAssertLessThan(move ?? 0, 0, "the text comes back down")
        XCTAssertEqual(top - (move ?? 0), landing, accuracy: 0.01)
    }

    func testTheMacsNumbers() {
        XCTAssertEqual(FollowTheVoice.trigger, 0.66)
        XCTAssertEqual(FollowTheVoice.landing, 0.33)
        XCTAssertEqual(FollowTheVoice.yield, 8)
    }
}
