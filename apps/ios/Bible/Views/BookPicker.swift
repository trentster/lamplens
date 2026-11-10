import SwiftUI

/// Where to read: books, then chapters, then verses — one decision per page, so the reader always
/// knows which choice they are making. The field at the top still takes a reference: "jn 3:16",
/// "ps 23", "1 cor 13".
struct BookPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let theme: Theme

    @State private var path = NavigationPath()
    @State private var query = ""
    /// nil until the reader works the control: the first render is already the testament they are
    /// reading, so the list they land in is the one holding their place.
    @State private var chosenTestament: Bool?

    private var testament: Bool {
        chosenTestament ?? store.book(of: store.position.chapter).newTestament
    }

    var body: some View {
        NavigationStack(path: $path) {
            books
                .navigationTitle("Books")
                .navigationBarTitleDisplayMode(.inline)
                .doneToolbar(dismiss)
                .navigationDestination(for: BookInfo.self) { book in
                    chapters(of: book)
                        .navigationTitle(book.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .doneToolbar(dismiss)
                        .navigationDestination(for: Int.self) { chapter in
                            verses(of: book, chapter: chapter)
                                .navigationTitle(chapterLabel(index: UInt16(chapter)))
                                .navigationBarTitleDisplayMode(.inline)
                                .doneToolbar(dismiss)
                        }
                }
        }
    }

    // MARK: - Page 1: the books

    private var books: some View {
        let here = store.book(of: store.position.chapter)
        let showing = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? store.bookList.filter { $0.newTestament == testament }
            : []
        return ScrollViewReader { proxy in
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else {
                    Section {
                        Picker("Testament", selection: Binding(
                            get: { testament },
                            set: { chosenTestament = $0 }
                        )) {
                            Text("Old Testament").tag(false)
                            Text("New Testament").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("testament")
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(showing, id: \.index) { book in
                            bookRow(book, current: book.index == here.index)
                                .id(book.index)
                        }
                    } header: {
                        Text(testament ? "New Testament" : "Old Testament")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Go to… (jn 3:16)"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) { goTyped() }
            .onAppear {
                // Opens with the book being read in view, not at Genesis.
                proxy.scrollTo(here.index, anchor: .center)
            }
            .onChange(of: testament) { _, new in
                // Coming back to the testament holding their place brings it into view again;
                // looking at the other one leaves the list where the reader put it.
                if store.book(of: store.position.chapter).newTestament == new {
                    proxy.scrollTo(here.index, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func bookRow(_ book: BookInfo, current: Bool) -> some View {
        NavigationLink(value: book) {
            HStack(spacing: 8) {
                Text(book.name)
                    .font(.body.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? Color(theme.accent) : Color(theme.ink))
                if current {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(theme.accent))
                }
                Spacer(minLength: 0)
                Text(book.chapters == 1 ? "1 chapter" : "\(book.chapters) chapters")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.ink2))
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(current ? Color(theme.accentSoft) : nil)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    @ViewBuilder
    private var suggestions: some View {
        let found = suggestReferences(input: query, limit: 8)
        Section {
            if found.isEmpty {
                Text("No book matches “\(query)”")
                    .foregroundStyle(Color(theme.ink2))
            }
            ForEach(found, id: \.label) { reference in
                Button {
                    store.go(to: reference)
                    dismiss()
                } label: {
                    Label(reference.label, systemImage: reference.verse == nil ? "book" : "text.quote")
                }
            }
        }
    }

    // MARK: - Page 2: the chapters

    private func chapters(of book: BookInfo) -> some View {
        let here = store.book(of: store.position.chapter)
        let current = here.index == book.index ? store.position.chapter : nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(book.chapters == 1 ? "1 chapter" : "\(book.chapters) chapters")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.ink2))
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8
                ) {
                    ForEach(1...Int(book.chapters), id: \.self) { n in
                        let index = Int(book.firstChapter) + n - 1
                        NavigationLink(value: index) {
                            Text("\(n)")
                                .font(.body.monospacedDigit().weight(index == current ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(index == current ? Color(theme.onAccent) : Color(theme.ink))
                                .background(
                                    index == current ? Color(theme.accent) : Color(theme.fill),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(book.name) \(n)")
                        .accessibilityAddTraits(index == current ? [.isSelected] : [])
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Page 3: the verses

    private func verses(of book: BookInfo, chapter: Int) -> some View {
        let count = store.verseCount(chapter)
        let local = chapter - Int(book.firstChapter) + 1
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    store.go(to: chapter)
                    dismiss()
                } label: {
                    Text("Read whole chapter")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Color(theme.onAccent))
                        .background(
                            Color(theme.accent), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wholeChapter")
                .accessibilityLabel("Read whole chapter, \(book.name) \(local)")

                Text("Or start at a verse")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.ink2))

                if count < 1 {
                    Text("This chapter could not be read, so its verses are unknown here.")
                        .font(.footnote)
                        .foregroundStyle(Color(theme.ink2))
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8
                    ) {
                        ForEach(1...count, id: \.self) { verse in
                            Button {
                                store.go(to: chapter, verse: verse, flash: true)
                                dismiss()
                            } label: {
                                Text("\(verse)")
                                    .font(.body.monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(Color(theme.ink))
                                    .background(
                                        Color(theme.fill),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(book.name) \(local):\(verse)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private func goTyped() {
        if let reference = parseReference(input: query) ?? suggestReferences(input: query, limit: 1).first {
            store.go(to: reference)
            dismiss()
        }
    }
}

private extension View {
    /// Done, on every page: a reader who has changed their mind should not have to walk back.
    func doneToolbar(_ dismiss: DismissAction) -> some View {
        toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("pickerDone")
            }
        }
    }
}
