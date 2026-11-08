import SwiftUI

/// Books and chapters, and a field that takes a reference: "jn 3:16", "ps 23", "1 cor 13".
struct BookPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    @State private var query = ""
    @State private var open: UInt8?
    /// Which chapter's verses are showing under a book's grid. Choosing one is not going there: it
    /// is what brings its verses up, so a verse can be chosen. The same as the Mac's picker.
    @State private var verseChapter: Int?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        testament("Old Testament", store.bookList.filter { !$0.newTestament })
                        testament("New Testament", store.bookList.filter(\.newTestament))
                    } else {
                        let suggestions = suggestReferences(input: query, limit: 8)
                        if suggestions.isEmpty {
                            Text("No book matches “\(query)”")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(suggestions, id: \.label) { reference in
                            Button {
                                go(reference)
                            } label: {
                                Label(reference.label, systemImage: reference.verse == nil ? "book" : "text.quote")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    let book = store.book(of: store.position.chapter).index
                    open = book
                    proxy.scrollTo(book, anchor: .center)
                }
            }
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Go to… (jn 3:16)"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                if let reference = parseReference(input: query) ?? suggestReferences(input: query, limit: 1).first {
                    go(reference)
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func testament(_ title: String, _ books: [BookInfo]) -> some View {
        Section(title) {
            ForEach(books, id: \.index) { book in
                row(book)
                    .id(book.index)
            }
        }
    }

    @ViewBuilder
    private func row(_ book: BookInfo) -> some View {
        let current = store.book(of: store.position.chapter).index == book.index
        Button {
            withAnimation(.smooth(duration: 0.25)) { open = open == book.index ? nil : book.index }
        } label: {
            HStack {
                Text(book.name)
                    .font(.body.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? Color(theme.accent) : .primary)
                Spacer()
                Text(book.chapters == 1 ? "1 chapter" : "\(book.chapters)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if book.chapters > 1 {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open == book.index ? 0 : -90))
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint("Shows its chapters and their verses")
        if open == book.index {
            verseWay(book)
        }
    }

    /// Choosing a verse: the book's chapters across the top, the chosen chapter's verses below.
    /// Neither list scrolls past the other, which is the rule the Mac's picker was built to.
    private func verseWay(_ book: BookInfo) -> some View {
        // Start on the chapter the reader is looking at, when it is in this book; else its first.
        let here = store.position.chapter
        let first = Int(book.firstChapter)
        let last = first + Int(book.chapters) - 1
        let chosen = verseChapter.flatMap { (first...last).contains($0) ? $0 : nil }
        let chapter = chosen ?? (store.book(of: here).index == book.index ? here : first)
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(1...Int(book.chapters), id: \.self) { n in
                    let index = Int(book.firstChapter) + n - 1
                    let current = index == chapter
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { verseChapter = index }
                    } label: {
                        Text("\(n)")
                            .font(.footnote.monospacedDigit().weight(current ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(current ? Color(theme.onAccent) : Color(theme.ink))
                            .background(
                                current ? Color(theme.accent) : Color(theme.fill),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(book.name) \(n)")
                }
            }
            verses(of: chapter, in: book)
        }
        .padding(.vertical, 4)
    }

    /// Every verse of a chapter on one screen, its verse numbers under the chapter it belongs to.
    private func verses(of chapter: Int, in book: BookInfo) -> some View {
        let count = store.verseCount(chapter)
        let local = chapter - Int(book.firstChapter) + 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(book.name) \(local), pick a verse")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Whole chapter") { go(chapter: chapter) }
                    .font(.footnote.weight(.semibold))
            }
            if count < 1 {
                Text("This chapter could not be read, so its verses are unknown here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], spacing: 6) {
                    ForEach(1...count, id: \.self) { verse in
                        Button {
                            store.go(to: chapter, verse: verse, flash: true)
                            dismiss()
                        } label: {
                            Text("\(verse)")
                                .font(.footnote.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(Color(theme.ink))
                                .background(
                                    Color(theme.fill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(book.name) \(local):\(verse)")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func go(chapter: Int) {
        store.go(to: chapter)
        dismiss()
    }

    private func go(_ reference: Reference) {
        store.go(to: reference)
        dismiss()
    }
}
