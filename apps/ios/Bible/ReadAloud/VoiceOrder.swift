import Foundation

/// Where a voice belongs in a list, and how it is described: the two things the first-run picker
/// and Settings must agree on, so neither can drift from the other.
///
/// British before American, and within each accent female before male; the name settles the rest,
/// which gives Freya, Spencer, Harper, Russell. No list of names is kept: a voice added to the
/// catalogue lands where it belongs by itself, and the name is the only tie-break.
struct VoiceOrder: Comparable {
    /// "UK" or "US", as the catalogue reports it.
    let accent: String
    let female: Bool
    let name: String

    /// "British female", "American male" — how the voice sounds, not how the data stores it. A
    /// reader choosing a voice is choosing how the words sound, and words per minute is not a
    /// word anyone uses for that.
    var described: String {
        "\(englishAccent) \(female ? "female" : "male")"
    }

    /// British and American are what the catalogue ships. Any other accent keeps its own code, so
    /// a voice that arrives later is described truly instead of being called American.
    private var englishAccent: String {
        if isBritish { return "British" }
        if accent.caseInsensitiveCompare("US") == .orderedSame { return "American" }
        return accent
    }

    private var isBritish: Bool { accent.caseInsensitiveCompare("UK") == .orderedSame }

    /// 0 for the British voices, 1 for the American ones, 2 for an accent this rule has not been
    /// taught yet: something new sorts last rather than jumping to the front.
    private var accentRank: Int {
        if isBritish { return 0 }
        return accent.caseInsensitiveCompare("US") == .orderedSame ? 1 : 2
    }

    static func < (a: VoiceOrder, b: VoiceOrder) -> Bool {
        if a.accentRank != b.accentRank { return a.accentRank < b.accentRank }
        if a.female != b.female { return a.female }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
