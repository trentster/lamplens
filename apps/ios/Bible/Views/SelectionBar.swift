import SwiftUI

/// What you can do with the verses you've tapped: highlight, note, bookmark, copy, share.
struct SelectionBar: View {
    @Environment(Store.self) private var store
    let theme: Theme

    var body: some View {
        let marks = store.selectionMarks
        let highlighted = Set(marks.compactMap(\.highlight))
        let bookmarked = !store.selectedRefs.isEmpty && marks.filter(\.bookmark).count == store.selectedRefs.count
        let anchor = store.selectionRef
        let canRelate = anchor.map(store.hasRelated) ?? false
        let canWords = anchor.map(store.hasOriginal) ?? false
        VStack(spacing: 12) {
            HStack {
                Text(store.selectionLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(theme.ink))
                    .lineLimit(1)
                Spacer()
                Button {
                    store.selection = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(theme.ink2))
                        .frame(width: 30, height: 30)
                        .background(Color(theme.fill), in: Circle())
                        // A menu that has risen over the page needs a way out big enough to hit.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("selectionClose")
            }

            HStack(spacing: 0) {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        store.highlightSelection(color)
                    } label: {
                        Circle()
                            .fill(Color(theme.swatch(color)))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if highlighted.contains(color) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Highlight \(color.label)")
                }
                Button {
                    store.highlightSelection(nil)
                } label: {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color(theme.ink3))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(highlighted.isEmpty)
                .opacity(highlighted.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Remove highlight")
            }

            HStack(spacing: 8) {
                action("Note", "note.text.badge.plus") { store.noteOnSelection() }
                action(bookmarked ? "Saved" : "Save", bookmarked ? "bookmark.fill" : "bookmark") {
                    store.toggleBookmarkOnSelection()
                }
                .accessibilityLabel(bookmarked ? "Remove bookmark" : "Bookmark")
                action("Copy", "doc.on.doc") { store.copySelection() }
                ShareLink(item: store.selectionText, subject: Text(store.selectionLabel)) {
                    label("Share", "square.and.arrow.up")
                }
                // The two rows below only appear when there is something behind them, so the bar
                // stays four wide for a verse the tradition links nowhere and we have no Hebrew for.
                if canRelate {
                    action("Related", "link") { store.sheet = .related }
                }
                if canWords {
                    action("Words", "text.book.closed") { store.sheet = .words }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        .solidCard(in: RoundedRectangle(cornerRadius: 28, style: .continuous), theme: theme)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { label(title, symbol) }
    }

    private func label(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(height: 22)
            Text(title)
                .font(.caption.weight(.medium))
                // No label may wrap: "Bookmark" broke onto two lines on a 12 Pro.
                .lineLimit(1)
        }
        .foregroundStyle(Color(theme.ink))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color(theme.fill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}
