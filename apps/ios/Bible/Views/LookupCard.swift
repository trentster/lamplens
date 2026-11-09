import SwiftUI

/// The card a held word opens: what the dictionaries say, in the Mac's order and the Mac's words —
/// WordNet first, then Easton's, then the KJV spellings that reach them.
///
/// Everything it reads is bundled, so the card answers with no network at all. There is deliberately
/// no Wiktionary link: Lamplit does not go looking outside itself.
struct LookupCard: View {
    @Environment(\.dismiss) private var dismiss
    let lookup: WordLookup
    let theme: Theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(lookup.reference)
                        .font(.caption)
                        .foregroundStyle(Color(theme.ink3))
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(line.isSource ? .caption : .callout)
                            .foregroundStyle(Color(line.isSource ? theme.ink3 : theme.ink))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .navigationTitle(lookup.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A card that slides up needs a way out that is not a drag.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("lookupDone")
                }
            }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("lookupCard")
    }

    private struct Line: Identifiable {
        let id = UUID()
        var text: String
        /// A dictionary's own name, or the note about a spelling, rather than what it says.
        var isSource = false
    }

    private var lines: [Line] {
        let found = define(word: lookup.word)
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
        let oneSource = Set(found.entries.map(\.source)).count == 1
        if oneSource, let source = found.entries.first?.source {
            out.append(Line(text: source, isSource: true))
        }
        for entry in found.entries {
            for paragraph in entry.body.split(separator: "\n") {
                let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { out.append(Line(text: trimmed)) }
            }
            if !oneSource { out.append(Line(text: entry.source, isSource: true)) }
        }
        return out
    }
}
