import XCTest

/// The one order and the one description both voice pickers use. `VoiceOrder.swift` is compiled
/// straight into this bundle, so these run in a moment with no app around them.
final class VoiceOrderTests: XCTestCase {
    private let catalogue = [
        ("Spencer", "UK", false),
        ("Russell", "US", false),
        ("Freya", "UK", true),
        ("Harper", "US", true),
    ]

    private func ordered(_ voices: [(String, String, Bool)]) -> [String] {
        voices
            .map { VoiceOrder(accent: $1, female: $2, name: $0) }
            .sorted()
            .map(\.name)
    }

    /// British before American, female before male within each: Freya, Spencer, Harper, Russell.
    /// Both pickers had a different order before this; neither keeps one now.
    func testBritishFirstFemaleFirst() {
        XCTAssertEqual(ordered(catalogue), ["Freya", "Spencer", "Harper", "Russell"])
    }

    /// The order does not depend on the order the catalogue happens to arrive in.
    func testTheOrderIsTheSameWhateverTheInputOrder() {
        let expected = ["Freya", "Spencer", "Harper", "Russell"]
        for shift in 0..<catalogue.count {
            let rotated = Array(catalogue[shift...] + catalogue[..<shift])
            XCTAssertEqual(ordered(rotated), expected, "rotated by \(shift)")
        }
        XCTAssertEqual(ordered(catalogue.reversed()), expected)
    }

    /// Nothing is hard-coded by name: a voice added to the catalogue falls in by accent and sex,
    /// and the name is only the tie-break between two voices that agree on both.
    func testANewVoiceFallsIntoPlace() {
        var withNew = catalogue
        withNew.append(("Michael", "US", false))
        XCTAssertEqual(ordered(withNew), ["Freya", "Spencer", "Harper", "Michael", "Russell"])
        // Two American men: the names decide, alphabetically.
        var twoMen = catalogue
        twoMen.append(("Aaron", "US", false))
        XCTAssertEqual(ordered(twoMen), ["Freya", "Spencer", "Harper", "Aaron", "Russell"])
    }

    /// An accent this rule has not been taught sorts last rather than jumping to the front.
    func testAnUnknownAccentSortsLast() {
        var voices = catalogue
        voices.append(("Siobhan", "IE", true))
        XCTAssertEqual(ordered(voices).last, "Siobhan")
    }

    /// Only the two accents the catalogue ships are given English names. Anything else shows its own
    /// code, so a voice added later says what it is rather than being called American.
    func testAnAccentOtherThanBritishOrAmericanKeepsItsCode() {
        XCTAssertEqual(VoiceOrder(accent: "AU", female: true, name: "Matilda").described, "AU female")
        XCTAssertEqual(VoiceOrder(accent: "AU", female: false, name: "Lee").described, "AU male")
        XCTAssertEqual(VoiceOrder(accent: "IE", female: true, name: "Siobhan").described, "IE female")
    }

    /// One description, in words a reader uses, and no words per minute anywhere.
    func testTheDescriptionIsPlainWords() {
        XCTAssertEqual(VoiceOrder(accent: "UK", female: true, name: "Freya").described, "British female")
        XCTAssertEqual(VoiceOrder(accent: "UK", female: false, name: "Spencer").described, "British male")
        XCTAssertEqual(VoiceOrder(accent: "US", female: true, name: "Harper").described, "American female")
        XCTAssertEqual(VoiceOrder(accent: "US", female: false, name: "Russell").described, "American male")
        for voice in catalogue {
            let described = VoiceOrder(accent: voice.1, female: voice.2, name: voice.0).described
            XCTAssertFalse(described.contains("wpm"), described)
            XCTAssertFalse(described.contains("·"), described)
        }
    }
}
