import Foundation

/// Whether the word a verse prints is the lexicon's own word, once the marks are taken off.
///
/// Hebrew prints a word with its vowel points and cantillation, Greek with its accents and
/// breathings; the lexicon lists the bare letters. A reader who taps בְּרֵאשִׁית lands on רֵאשִׁית and
/// looks for the ב that opened it. Where the letters themselves differ the entry owes the reader the
/// form as written; where only the marks differ (אֱלֹהִים against אֱלֹהִים, γὰρ against γάρ) it is one
/// word printed twice and the entry says nothing.
enum WordForm {
    /// The letters alone: combining marks gone, case folded, final sigma as sigma, punctuation gone
    /// (the maqaf and the sof pasuq among it). Decomposing first turns a precomposed ἄ into α and a
    /// separate accent, so one rule covers both the Latin-style accents and the Hebrew points.
    static func letters(_ word: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in word.decomposedStringWithCanonicalMapping.unicodeScalars {
            guard !CharacterSet.nonBaseCharacters.contains(scalar),
                CharacterSet.letters.contains(scalar)
            else { continue }
            kept.append(scalar)
        }
        return String(kept).lowercased().replacingOccurrences(of: "ς", with: "σ")
    }

    /// True when the verse's form and the entry's own word are not the same letters: the only case
    /// in which the entry names the form the reader actually tapped.
    static func differs(verse: String, lemma: String) -> Bool {
        let written = letters(verse)
        return !written.isEmpty && written != letters(lemma)
    }

    /// What VoiceOver says for the form in the verse: "In this verse, written bereShit". The script
    /// itself would be spelled out letter by letter.
    static func spoken(translit: String) -> String {
        "In this verse, written \(sayable(translit))"
    }

    /// A transliteration as speech. The written form keeps its dots — they separate the syllables —
    /// but VoiceOver may say the dot aloud ("re dot shit"), so every spoken label goes without them.
    static func sayable(_ translit: String) -> String {
        translit.replacingOccurrences(of: ".", with: "")
    }
}
