import XCTest

/// When an entry owes the reader the form the verse actually prints. `WordForm.swift` is compiled
/// straight into this bundle, so these run in a moment with no app around them.
final class WordFormTests: XCTestCase {
    /// The case that started this: the ב that opens bereShit is not in the dictionary's word, so the
    /// entry shows what the reader tapped.
    func testAPrefixTheEntryDoesNotShowIsShown() {
        XCTAssertTrue(WordForm.differs(verse: "בְּרֵאשִׁית", lemma: "רֵאשִׁית"))
        XCTAssertEqual(WordForm.letters("בְּרֵאשִׁית"), "בראשית")
        XCTAssertEqual(WordForm.letters("רֵאשִׁית"), "ראשית")
    }

    /// Genesis 1:1 prints elohim with cantillation; the lexicon lists the letters. One word.
    func testCantillationAloneIsTheSameWord() {
        XCTAssertFalse(WordForm.differs(verse: "אֱלֹהִים\u{0591}", lemma: "אֱלֹהִים"))
        XCTAssertFalse(WordForm.differs(verse: "אֱלֹהִים", lemma: "אֱלֹהִים"))
        XCTAssertEqual(WordForm.letters("אֱלֹהִים\u{0591}"), "אלהים")
    }

    /// A grave and an acute are the same word: accent-only differences say nothing to a reader.
    func testAnAccentAloneIsTheSameWord() {
        XCTAssertFalse(WordForm.differs(verse: "γὰρ", lemma: "γάρ"))
        XCTAssertEqual(WordForm.letters("γὰρ"), "γαρ")
        XCTAssertEqual(WordForm.letters("γάρ"), "γαρ")
    }

    /// τῆς in the verse against the article's own ὁ: different letters, so the entry shows the form.
    func testADifferentWordIsShown() {
        XCTAssertTrue(WordForm.differs(verse: "τῆς", lemma: "ὁ"))
        // The final sigma folds to a sigma, which is why the two differ in the letters and not only
        // in their marks.
        XCTAssertEqual(WordForm.letters("τῆς"), "τησ")
        XCTAssertEqual(WordForm.letters("ὁ"), "ο")
    }

    /// Punctuation follows the letters and goes with the marks: a maqaf or a sof pasuq changes
    /// nothing.
    func testPunctuationIsNotALetter() {
        XCTAssertEqual(WordForm.letters("בְּרֵאשִׁית־"), "בראשית")
        XCTAssertEqual(WordForm.letters("אֱלֹהִים׃"), "אלהים")
        XCTAssertFalse(WordForm.differs(verse: "אֱלֹהִים׃", lemma: "אֱלֹהִים"))
    }

    /// An entry opened with no verse form behind it says nothing at all.
    func testNoVerseFormSaysNothing() {
        XCTAssertFalse(WordForm.differs(verse: "", lemma: "רֵאשִׁית"))
        XCTAssertFalse(WordForm.differs(verse: "־", lemma: "רֵאשִׁית"))
    }

    /// VoiceOver hears words, not dots: "In this verse, written bereShit".
    func testVoiceOverReadsTheTransliterationWithoutItsDots() {
        XCTAssertEqual(WordForm.spoken(translit: "be.re.Shit"), "In this verse, written bereShit")
    }

    /// The same rule everywhere a transliteration is spoken, including the entry's
    /// "pronounced" label: the written form keeps its dots, the spoken one never has them.
    func testEverySpokenTransliterationLosesItsDots() {
        XCTAssertEqual(WordForm.sayable("re.shit"), "reshit")
        XCTAssertEqual(WordForm.sayable("ap.ok.ar.ad.ok.ee\u{2019}ah"), "apokaradokee\u{2019}ah")
        XCTAssertEqual(WordForm.sayable("be.re.Shit"), "bereShit")
        XCTAssertEqual(WordForm.sayable("ho"), "ho")
    }
}
