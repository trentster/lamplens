import SwiftUI

/// The verse in the language it was written in: each word with how it sounds and the gloss
/// translators give it. Tapping a word opens the dictionary entry behind its number.
///
/// The Mac offers this from one word in the text; a phone has no room for that, so it lives on the
/// verse you have tapped, in the bar, only when there is original text to show.
struct WordsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ref: VerseRef
    let theme: Theme

    var body: some View {
        let verse = store.original(ref)
        NavigationStack {
            Group {
                if let verse, !verse.words.isEmpty {
                    OriginalWordsList(verse: verse, theme: theme)
                } else {
                    ContentUnavailableView {
                        Label("No original text", systemImage: "text.book.closed")
                    } description: {
                        Text("We have no Hebrew or Greek for \(label).")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var label: String { rangeLabel(from: ref, to: ref) }

    private var title: String {
        guard let language = store.original(ref)?.language else { return label }
        return "\(language) · \(label)"
    }

}

/// The words of one verse, with how each sounds and the gloss translators give it, and the credit at
/// the foot. Shared by the verse menu's Words button and the definition card's original-words row,
/// so the two never drift apart.
struct OriginalWordsList: View {
    @Environment(Store.self) private var store
    let verse: OriginalVerse
    let theme: Theme
    /// The page's title when this is a page of its own: "Hebrew words". The words sheet names the
    /// verse it is showing instead, so it passes nothing and keeps its own title. Both read the
    /// language from `verse.language`, which is what the row that leads here says.
    var title: String?

    var body: some View {
        if let title {
            list.navigationTitle(title)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(Array(verse.words.enumerated()), id: \.offset) { _, word in
                    NavigationLink {
                        EntryView(word: word, language: verse.language, theme: theme)
                    } label: {
                        wordRow(word)
                    }
                    // Named by its number so the review can tap a known word: the script itself is
                    // the one thing a predicate cannot spell reliably.
                    .accessibilityIdentifier("word-\(word.strong)")
                }
            } footer: {
                Text(store.wordsCreditLine)
                    .font(.caption)
                    .foregroundStyle(Color(theme.ink3))
            }
            .listRowBackground(Color(theme.fillStrong))
        }
        .listStyle(.insetGrouped)
    }

    private func wordRow(_ word: OriginalWord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // One line, whatever the word's length. A script word broken mid-word — apokaradoki
            // with a lone alpha beneath it — cannot be read, so the word keeps its width and the
            // transliteration and gloss beside it wrap onto as many lines as they need.
            Text(word.surface)
                .font(.system(size: 24))
                .foregroundStyle(Color(theme.ink))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.translit)
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.ink2))
                Text(word.gloss)
                    .font(.footnote)
                    .foregroundStyle(Color(theme.ink3))
            }
            // The row's remaining width, so the two lines beside the word wrap inside it instead
            // of running off the card's edge at the largest text sizes.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

/// One lexicon entry: the word in its own script as the page's title, then how it is said and what
/// it means, line by line by line. The Strong's number stays in the small grey line, because it is
/// how the lexicons are keyed, not what a reader came to read.
struct EntryView: View {
    @Environment(Store.self) private var store
    let word: OriginalWord
    /// "Hebrew" or "Greek", from the verse these words came from, so the page can say what the word
    /// is a word of and VoiceOver can read it instead of spelling the script out.
    let language: String
    let theme: Theme

    /// What VoiceOver says for the word: "Hebrew word, pronounced re.shit". The script itself would
    /// be spelled out letter by letter, which is not what a reader wants to hear.
    private var spoken: String {
        let said = store.entry(word.strong)?.translit ?? word.translit
        // Spoken, not written: the dots that separate syllables are read out as "dot".
        return "\(language) word, pronounced \(WordForm.sayable(said))"
    }

    var body: some View {
        let entry = store.entry(word.strong)
        List {
            if let entry {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.lemma)
                            .font(.system(size: 28))
                            .foregroundStyle(Color(theme.ink))
                            .accessibilityLabel(spoken)
                        // Always on its own line, so the card is the same shape for a short word and
                        // a long one.
                        Text("pronounced \(entry.translit)")
                            .font(.subheadline)
                            .foregroundStyle(Color(theme.ink2))
                        Text(entry.short)
                            .font(.body)
                            .foregroundStyle(Color(theme.ink))
                        // The form as the verse prints it, and only when its letters are not the
                        // entry's own: the ב that opens bereShit is why a reader tapped it, and
                        // without this line the entry looks as though it lost a letter.
                        if WordForm.differs(verse: word.surface, lemma: entry.lemma) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("In this verse:")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(theme.ink2))
                                Text(word.surface)
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color(theme.ink))
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(WordForm.spoken(translit: word.translit))
                        }
                        Text("\(entry.id) · \(entry.pos)")
                            .font(.caption)
                            .foregroundStyle(Color(theme.ink3))
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(theme.fillStrong))
                Section {
                    ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(Color(theme.ink2))
                    }
                }
                .listRowBackground(Color(theme.fillStrong))
            } else {
                Section {
                    Text("No entry for \(word.strong)")
                        .foregroundStyle(Color(theme.ink2))
                } footer: {
                    Text(store.wordsCreditLine)
                        .font(.caption)
                        .foregroundStyle(Color(theme.ink3))
                }
                .listRowBackground(Color(theme.fillStrong))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(entry?.lemma ?? word.strong).accessibilityLabel(spoken))
        .navigationBarTitleDisplayMode(.inline)
    }
}
