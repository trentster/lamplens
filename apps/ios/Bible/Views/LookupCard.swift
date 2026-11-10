import SwiftUI

/// The card a held word opens: what the dictionaries say, in the Mac's order and the Mac's words —
/// WordNet first, then Easton's, then the KJV spellings that reach them — and, when the verse has
/// original text, the way in to the words behind it.
///
/// Everything it reads is bundled, so the card answers with no network at all. There is deliberately
/// no Wiktionary link: Lamplit does not go looking outside itself.
struct LookupCard: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let lookup: WordLookup
    let theme: Theme

    var body: some View {
        let original = store.original(store.ref(chapter: lookup.chapter, verse: lookup.verse))
        let found = define(word: lookup.word)
        let pinned = pinnedSource(found)
        let entries = bodyLines(found, pinned: pinned)
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { line in
                            Text(line.text)
                                .font(line.isSource ? .caption : .callout)
                                .foregroundStyle(Color(line.isSource ? theme.ink3 : theme.ink))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                }
                // The dictionary's name sits at the foot, quietly, as the Mac draws it: a long entry
                // scrolling past does not take the provenance with it, and there is no rule above
                // it, because a full-width line at the bottom reads as a bar with more behind it.
                if let pinned {
                    HStack {
                        Text("Source: \(pinned)")
                            .font(.system(.caption2, design: .serif))
                            .italic()
                            .foregroundStyle(Color(theme.ink2))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                if let original, !original.words.isEmpty {
                    originalRow(original)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A card that slides up needs a way out that is not a drag.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("lookupDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("lookupCard")
    }

    /// As the Mac draws it: the word, the place it was found, then a rule across the card.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lookup.word)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color(theme.ink))
                .fixedSize(horizontal: false, vertical: true)
            Text(lookup.reference)
                .font(.caption)
                .foregroundStyle(Color(theme.ink2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color(theme.separator))
                .frame(height: 1)
        }
    }

    /// The way into the verse's own words, when it has any: what language, how many words, and a
    /// chevron. The Mac offers this from a word in the text; a phone reaches it from here.
    private func originalRow(_ original: OriginalVerse) -> some View {
        let count = original.words.count
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color(theme.separator))
                .frame(height: 1)
            NavigationLink {
                OriginalWordsList(verse: original, theme: theme)
            } label: {
                HStack(spacing: 8) {
                    Text(original.language)
                        .font(.body)
                        .foregroundStyle(Color(theme.ink))
                    Text(count == 1 ? "1 word" : "\(count) words")
                        .font(.subheadline)
                        .foregroundStyle(Color(theme.ink3))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(theme.ink3))
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lookupOriginalWords")
        }
    }

    private struct Line: Identifiable {
        let id = UUID()
        var text: String
        /// A dictionary's own name, or the note about a spelling, rather than what it says.
        var isSource = false
    }

    /// Where the Mac pins one dictionary's name at the foot, this card does too; where the Mac has
    /// more than one, each entry carries its own name instead.
    private func pinnedSource(_ found: Definition) -> String? {
        guard !found.entries.isEmpty else { return nil }
        let sources = Set(found.entries.map(\.source))
        return sources.count == 1 ? found.entries.first?.source : nil
    }

    private func bodyLines(_ found: Definition, pinned: String?) -> [Line] {
        guard !found.entries.isEmpty else {
            // The Mac's wording for the case where neither dictionary has it.
            return [Line(text: "No definition found")]
        }
        var out: [Line] = []
        // The KJV's spelling is not always the dictionary's headword, and the reader deserves to
        // know why they are being shown a different word.
        if let headword = found.shownAs {
            out.append(Line(text: "“\(lookup.word)” — shown as \(headword)", isSource: true))
        }
        for entry in found.entries {
            for paragraph in entry.body.split(separator: "\n") {
                let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { out.append(Line(text: trimmed)) }
            }
            if pinned == nil { out.append(Line(text: entry.source, isSource: true)) }
        }
        return out
    }
}
