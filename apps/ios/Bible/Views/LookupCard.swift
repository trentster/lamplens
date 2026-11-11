import SwiftUI

/// The card a held word opens: what the dictionaries say, in the Mac's order and the Mac's words —
/// WordNet first, then Easton's, then the KJV spellings that reach them — and, when the verse has
/// original text, the way in to the words behind it.
///
/// Everything it reads is bundled, so the card answers with no network at all. There is deliberately
/// no Wiktionary link: Lamplens does not go looking outside itself.
///
/// On a phone the card's first page is exactly as tall as what is on it, so a short definition does
/// not leave a gap and the verse it came from stays in view. The words list and an entry behind it
/// take the full sheet, and coming back fits the card again.
struct LookupCard: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Not read for its value: a phone turned on its side changes it, which re-measures the card at
    /// the new width.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let lookup: WordLookup
    let theme: Theme

    /// The first page's height without the navigation bar, measured from a hidden copy laid out at
    /// the sheet's real width. `nil` until it has been measured.
    @State private var pageHeight: CGFloat?
    /// The navigation bar's height, read from the page's top safe-area inset.
    @State private var barHeight: CGFloat = 0
    /// True while the words list or an entry is showing: those pages take the full sheet.
    @State private var deeper = false
    /// True when the reader dragged the first page up to full height themselves.
    @State private var expanded = false

    var body: some View {
        let original = store.original(store.ref(chapter: lookup.chapter, verse: lookup.verse))
        let found = define(word: lookup.word)
        let pinned = pinnedSource(found)
        let entries = bodyLines(found, pinned: pinned)
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    definitions(entries)
                }
                // The dictionary's name sits at the foot, quietly, as the Mac draws it: a long entry
                // scrolling past does not take the provenance with it, and there is no rule above
                // it, because a full-width line at the bottom reads as a bar with more behind it.
                if let pinned {
                    sourceLine(pinned)
                }
                if let original, !original.words.isEmpty {
                    NavigationLink {
                        OriginalWordsList(verse: original, theme: theme, title: "\(original.language) words")
                            .onAppear { deeper = true }
                    } label: {
                        originalRow(original)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lookupOriginalWords")
                }
            }
            // Back on the first page, from the words list or from launch: it fits again.
            .onAppear { deeper = false }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { barHeight = $0 }
            .background(alignment: .top) {
                // The page as it would stand at the sheet's real width, never drawn and never read
                // out, so its height is right from the first layout. Measuring the page itself is
                // not enough: a sheet's first layout pass is about half as wide as the sheet, which
                // makes text twice as tall, and the card would open tall and then shrink.
                if let width = Self.sheetWidth {
                    measuredPage(entries: entries, pinned: pinned, original: original)
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
                        .hidden()
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
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
        .presentationDetents(detents, selection: detentSelection)
        .accessibilityIdentifier("lookupCard")
    }

    // MARK: - Height

    /// The sheet a phone presents spans the screen's width, portrait or landscape, so that is the
    /// width the hidden copy is laid out at. Anywhere else (an iPad's narrower form sheet) there is
    /// no width to trust, and the card keeps the fixed heights it always had.
    @MainActor private static var sheetWidth: CGFloat? {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return nil }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen.bounds.width
    }

    /// The first page's own height, once both parts of it are known: the page and the bar above it.
    /// Rounded up, with a point to spare, so the last line is never clipped by a rounding.
    private var fitted: PresentationDetent? {
        guard let pageHeight, pageHeight > 0, barHeight > 0 else { return nil }
        return .height((pageHeight + barHeight).rounded(.up) + 1)
    }

    /// Fitted and full while the card can be measured; the old medium and full while it cannot.
    private var detents: Set<PresentationDetent> {
        if let fitted { return [fitted, .large] }
        return [.medium, .large]
    }

    /// Which height the sheet is at, worked out rather than stored, so it is always one of `detents`:
    /// full for the pages behind the card or when the reader pulled it up, fitted otherwise.
    private var detentSelection: Binding<PresentationDetent> {
        Binding(
            get: { deeper || expanded ? .large : (fitted ?? .medium) },
            set: { expanded = !deeper && $0 == .large }
        )
    }

    /// The first page as the hidden copy draws it: the same parts, with the definitions at their
    /// full length rather than in a scroll view, and the words row's label without its link.
    private func measuredPage(entries: [Line], pinned: String?, original: OriginalVerse?) -> some View {
        VStack(spacing: 0) {
            header
            definitions(entries)
            if let pinned {
                sourceLine(pinned)
            }
            if let original, !original.words.isEmpty {
                originalRow(original)
            }
        }
    }

    // MARK: - Parts

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

    /// What the dictionaries say, line by line.
    private func definitions(_ entries: [Line]) -> some View {
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

    private func sourceLine(_ pinned: String) -> some View {
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

    /// The way into the verse's own words, when it has any: what language, how many words, and a
    /// chevron. The Mac offers this from a word in the text; a phone reaches it from here.
    private func originalRow(_ original: OriginalVerse) -> some View {
        let count = original.words.count
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color(theme.separator))
                .frame(height: 1)
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
    }

    // MARK: - What the dictionaries say

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
