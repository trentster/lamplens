import Foundation
import Observation
import UIKit
import os

/// The reader's preferences, saved in the study database (under the "ios" setting) as JSON.
struct ReaderSettings: Codable, Equatable {
    var translation = "kjv"
    var appearance = Appearance.system
    /// Points at the default Dynamic Type size.
    var textSize: Double = 18
    var lineSpacing: Double = 1.6
    var redLetters = true
    var verseNumbers = true
    var versePerLine = false
    var headings = true
    var wholeWords = false
    /// False until the first-launch screen has been answered. Saved with the rest, so it is asked
    /// once and never again; everything it sets stays changeable in Settings.
    var didFirstRun = false

    static let textSizes: ClosedRange<Double> = 14...32
    static let lineSpacings: ClosedRange<Double> = 1.3...2.0

    init() {}

    /// Settings saved by an older or newer build decode too: anything missing keeps its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        translation = value(.translation, d.translation)
        appearance = value(.appearance, d.appearance)
        textSize = value(.textSize, d.textSize).clamped(to: Self.textSizes)
        lineSpacing = value(.lineSpacing, d.lineSpacing).clamped(to: Self.lineSpacings)
        redLetters = value(.redLetters, d.redLetters)
        verseNumbers = value(.verseNumbers, d.verseNumbers)
        versePerLine = value(.versePerLine, d.versePerLine)
        headings = value(.headings, d.headings)
        wholeWords = value(.wholeWords, d.wholeWords)
        didFirstRun = value(.didFirstRun, d.didFirstRun)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// A chapter (0–1188 in the canonical grid) and verse.
/// A word held down on the page, and the verse it was pressed in.
struct WordLookup: Identifiable, Equatable {
    let id = UUID()
    var word: String
    var chapter: Int
    var verse: Int
    var reference: String
}

struct Position: Equatable {
    var chapter: Int
    var verse: Int
}

/// A request for the reader to move.
struct JumpRequest: Equatable {
    let id = UUID()
    var chapter: Int
    var verse: Int
    var animated = false
    var flash = false
}

enum Sheet: Identifiable, Equatable {
    case books, search, settings, study, related, words, voiceChooser
    case note(VerseRef)
    case lookup(WordLookup)

    var id: String {
        switch self {
        case .books: "books"
        case .search: "search"
        case .settings: "settings"
        case .study: "study"
        case .related: "related"
        case .words: "words"
        case .voiceChooser: "voiceChooser"
        case .lookup: "lookup"
        case .note(let v): "note-\(v.book)-\(v.chapter)-\(v.verse)"
        }
    }
}

@MainActor
@Observable
final class Store {
    @ObservationIgnored let bible: Bible
    @ObservationIgnored let bookList: [BookInfo]
    private(set) var translations: [TranslationInfo]

    var settings: ReaderSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.translation != oldValue.translation { translationChanged() }
            scheduleSave()
        }
    }

    /// Where the reader is; the reader view reports it as you scroll.
    private(set) var position: Position
    private(set) var jump: JumpRequest?
    var selection: VerseSelection?
    /// Bumped whenever highlights, notes or bookmarks change.
    private(set) var marksVersion = 0
    var sheet: Sheet?
    /// Whether the toolbar and the status bar are away. Private so every change goes through a named
    /// method below, and the rules about when the bars show live in this one file.
    private(set) var barsHidden = false
    /// Read Aloud: the voice, the audio and the timer.
    let speaker = Speaker()
    private(set) var toast: String?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        let bible = Self.openBible()
        let bookList = books()
        let translations = bible.translations()
        var settings = ReaderSettings()
        var position = Position(chapter: Int(bookList[42].firstChapter), verse: 1)
        if let json = bible.setting(key: "ios"), let saved = try? JSONDecoder().decode(Saved.self, from: Data(json.utf8)) {
            settings = saved.settings ?? settings
            if let chapter = saved.chapter, (0..<ReaderView.chapterCount).contains(chapter) {
                position = Position(chapter: chapter, verse: max(saved.verse ?? 1, 1))
            }
        }
        if !translations.contains(where: { $0.id == settings.translation }) {
            settings.translation = translations.first?.id ?? "kjv"
        }
        // A test run starts at the reader, because every test but one is about the page. The test
        // that asks for the first launch says so, and gets the questions back even though a
        // container from an earlier run has the answer saved.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest") {
            settings.didFirstRun = !arguments.contains("--first-run")
        }
        self.bible = bible
        self.bookList = bookList
        self.translations = translations
        self.settings = settings
        self.position = position
        #if DEBUG
            ReaderStateDebug.store = self
        #endif
        jump = JumpRequest(chapter: position.chapter, verse: position.verse)
        // A UI test can ask for one word's card by name, so the case where nothing defines the word
        // can be shown without hunting for such a word in the text. Not behind #if DEBUG: the UI
        // suite runs the Release configuration, where DEBUG is compiled out, and it needs the hook.
        // Only --uitest reaches it, which no real launch passes.
        if arguments.contains("--uitest"), let i = arguments.firstIndex(of: "--lookup"),
            i + 1 < arguments.count
        {
            // After the first layout pass: a sheet asked for during the very first body evaluation
            // is dropped, which is why this card never appeared in the test.
            let word = arguments[i + 1]
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                self?.lookUp(
                    word: word, chapter: self?.position.chapter ?? 0,
                    verse: self?.position.verse ?? 1)
            }
        }
    }

    /// The study database and imported texts live in Application Support. If that can't be
    /// opened the reader still works, keeping study data in a temporary folder.
    private static func openBible() -> Bible {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = support.appendingPathComponent("bible-rs", isDirectory: true)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest") {
            // UI tests start from nothing (unless relaunching) and leave your notes alone.
            dir = fm.temporaryDirectory.appendingPathComponent("bible-rs-uitest", isDirectory: true)
            if !arguments.contains("--keep-data") { try? fm.removeItem(at: dir) }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            return try Bible(dataDir: dir.path)
        } catch {
            Log.app.error("Couldn't open \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let tmp = fm.temporaryDirectory.appendingPathComponent("bible-rs", isDirectory: true)
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            return try! Bible(dataDir: tmp.path)
        }
    }

    // MARK: Text

    var translation: TranslationInfo? { translations.first { $0.id == settings.translation } }

    var contentOptions: ContentOptions {
        ContentOptions(
            versePerLine: settings.versePerLine, headings: settings.headings, verseNumbers: settings.verseNumbers)
    }

    /// Decodes the translation and builds its search text off the main thread.
    func warm() {
        let bible = bible
        let ids = [settings.translation]
        Task.detached(priority: .utility) { bible.warm(translations: ids) }
    }

    private func translationChanged() {
        stopReading()
        selection = nil
        warm()
    }

    // MARK: Books and chapters

    func book(of chapter: Int) -> BookInfo {
        bookList.last { Int($0.firstChapter) <= chapter } ?? bookList[0]
    }

    func ref(chapter: Int, verse: Int) -> VerseRef {
        let book = book(of: chapter)
        return VerseRef(book: book.index, chapter: UInt8(chapter - Int(book.firstChapter) + 1), verse: UInt8(verse))
    }

    /// The whole-Bible chapter index for a book and one of its own chapters. Cross references name
    /// a book and a chapter inside it, while the reader moves by whole-Bible index.
    func chapterIndex(book: UInt8, chapter: UInt8) -> Int? {
        guard let info = bookList.first(where: { $0.index == book }), chapter >= 1 else { return nil }
        let index = Int(info.firstChapter) + Int(chapter) - 1
        return index < Int(info.firstChapter) + Int(info.chapters) ? index : nil
    }

    var title: String { chapterLabel(index: UInt16(position.chapter)) }

    /// Where the page is, as a place: book and chapter, never a verse — the Mac labels places the
    /// same way. The short form is the core's own SBL abbreviation, for when the full name does not
    /// fit. "Where am I" is the most important thing on the screen, so it is never an ellipsis.
    var placeTitle: (full: String, short: String) {
        let book = book(of: position.chapter)
        let chapter = position.chapter - Int(book.firstChapter) + 1
        return ("\(book.name) \(chapter)", "\(book.abbrev) \(chapter)")
    }

    // MARK: Moving

    func go(to chapter: Int, verse: Int = 1, flash: Bool = false, animated: Bool = false) {
        // The Mac stops a reading only when the page leaves the chapter being read (Listen::leaving).
        // A jump inside it — a search hit, a reference, a related verse — leaves the reading going.
        if speaker.chapter != chapter { stopReading() }
        selection = nil
        showBars()
        position = Position(chapter: chapter, verse: verse)
        jump = JumpRequest(chapter: chapter, verse: verse, animated: animated, flash: flash)
        scheduleSave()
    }

    func go(to reference: Reference) {
        go(to: Int(reference.chapterIndex), verse: Int(reference.verse ?? 1), flash: reference.verse != nil)
    }

    func reached(_ chapter: Int, verse: Int) {
        let next = Position(chapter: chapter, verse: verse)
        guard next != position else { return }
        position = next
        scheduleSave()
    }

    // MARK: Selection

    func tap(verse: Int, chapter: Int) {
        showBars()
        if var s = selection, s.chapter == chapter {
            if s.verses.contains(verse) { s.verses.remove(verse) } else { s.verses.insert(verse) }
            selection = s.verses.isEmpty ? nil : s
        } else {
            selection = VerseSelection(chapter: chapter, verses: [verse])
        }
    }

    func tapPage() {
        if selection != nil {
            selection = nil
        } else {
            // An empty page: the reader tapped it to get the bars out of the way, or to bring them
            // back.
            barsHidden.toggle()
        }
    }

    /// The bars come back whenever the reader goes somewhere or asks for something.
    func showBars() {
        barsHidden = false
    }

    /// Scrolling down the page hides the bars; scrolling up brings them back. A selection keeps them
    /// on screen, because the reader is working with the verses it covers.
    func scrollHidesBars(_ hide: Bool) {
        guard selection == nil, barsHidden != hide else { return }
        barsHidden = hide
    }

    var selectedRefs: [VerseRef] {
        guard let s = selection else { return [] }
        return s.verses.sorted().map { ref(chapter: s.chapter, verse: $0) }
    }

    /// "John 3:16", "John 3:16–18" or "John 3:16, 18".
    var selectionLabel: String {
        let refs = selectedRefs
        guard let first = refs.first, let last = refs.last else { return "" }
        let contiguous = Int(last.verse) - Int(first.verse) == refs.count - 1
        if contiguous { return rangeLabel(from: first, to: last) }
        return rangeLabel(from: first, to: first) + ", " + refs.dropFirst().map { "\($0.verse)" }.joined(separator: ", ")
    }

    var selectionMarks: [VerseMarks] {
        guard let s = selection else { return [] }
        return bible.marks(translation: settings.translation, chapter: UInt16(s.chapter))
            .filter { s.verses.contains(Int($0.verse)) }
    }

    func highlightSelection(_ color: HighlightColor?) {
        study { for ref in selectedRefs { try bible.setHighlight(verse: ref, color: color) } }
        selection = nil
    }

    func toggleBookmarkOnSelection() {
        let refs = selectedRefs
        let marked = Set(selectionMarks.filter(\.bookmark).map(\.verse))
        let on = refs.contains { !marked.contains($0.verse) }
        study { for ref in refs { try bible.setBookmark(verse: ref, on: on) } }
        show(on ? (refs.count == 1 ? "Bookmarked" : "Bookmarked \(refs.count) verses") : "Bookmark removed")
        selection = nil
    }

    func noteOnSelection() {
        guard let first = selectedRefs.first else { return }
        openNote(first)
    }

    /// Writing a note is not listening: the reading pauses, and the bar shows Paused so it is clear
    /// where it got to. It does not start again by itself when the note closes — Play is the
    /// reader's to press. (Nobody keeps listening while they write, so they would pause anyway; and
    /// the bar used to ride up the keyboard above the note card, where its stop button sat where a
    /// thumb expects the card's close button.) Notes only: the lookup card pauses nothing.
    func openNote(_ ref: VerseRef) {
        #if DEBUG
            // Every way into a note comes through here. The reading is left alone: Mark's rule,
            // matching the Mac, is that it stops only when the reader stops it.
            Breadcrumbs.mark("openNote: reading is \(speaker.phase)")
        #endif
        sheet = .note(ref)
    }

    /// The selected verses as text with their reference, as the Mac copies them.
    var selectionText: String {
        (try? bible.copyText(translation: settings.translation, verses: selectedRefs)) ?? ""
    }

    func copySelection() {
        UIPasteboard.general.string = selectionText
        show("Copied \(selectionLabel)")
        selection = nil
    }

    // MARK: Study

    func note(_ ref: VerseRef) -> String { (try? bible.note(verse: ref)) ?? "" }

    @discardableResult
    func setNote(_ ref: VerseRef, _ body: String) -> Bool {
        study { try bible.setNote(verse: ref, body: body) }
    }

    func setHighlight(_ ref: VerseRef, _ color: HighlightColor?) {
        study { try bible.setHighlight(verse: ref, color: color) }
    }

    /// Removes one of a verse's highlights (a study item's `start`), leaving its others.
    func removeHighlight(_ ref: VerseRef, _ start: UInt32) {
        study { try bible.removeHighlight(verse: ref, start: start) }
    }

    func setBookmark(_ ref: VerseRef, _ on: Bool) {
        study { try bible.setBookmark(verse: ref, on: on) }
    }

    func items(_ kind: StudyKind) -> [StudyItem] {
        bible.studyItems(kind: kind, translation: settings.translation)
    }

    // MARK: - Read Aloud

    /// How many verses a chapter has, for the picker's grid. Read from the chapter itself, so a
    /// translation with a different versification is followed rather than assumed.
    func verseCount(_ chapter: Int) -> Int {
        let content = bible.chapter(
            translation: settings.translation, index: UInt16(chapter), options: contentOptions)
        let numbers = content.blocks.flatMap { block in
            [Int(block.gutterVerse)] + block.runs.map { Int($0.verse) }
        }
        return numbers.max() ?? 0
    }

    /// The verses of a chapter as Read Aloud says them, opening announcement and all.
    func spoken(_ chapter: Int, from verse: Int? = nil) -> [SpokenUtterance] {
        Breadcrumbs.mark("asking for chapter \(chapter) to read")
        defer { Breadcrumbs.mark("chapter \(chapter) ready to read") }
        return (try? bible.spokenChapter(
            translation: settings.translation, index: UInt16(chapter),
            from: verse.map { UInt8(clamping: $0) })) ?? []
    }

    /// Starts the reading where the page is standing, or stops the one that is running.
    func toggleReading() {
        if speaker.phase.isOn {
            speaker.stop()
            return
        }
        // A reader who has never chosen a voice is asked once, at the moment they want to listen.
        guard speaker.hasChosenVoice else {
            sheet = .voiceChooser
            return
        }
        startReading()
    }

    /// Starts at the verse at the reading line, with the voice that has been chosen.
    func startReading() {
        speaker.chapterTitle = { chapter in chapterLabel(index: UInt16(clamping: chapter)) }
        // The voice follows the page: it starts at the verse at the reading line, not the top.
        speaker.start(chapterIndex: position.chapter, fromVerse: Int(position.verse)) { [weak self] index, from in
            (self?.spoken(index, from: from) ?? [], index)
        }
    }

    /// After a failure, one tap tries again from where the page is, and plays: someone who pressed
    /// Play once should not have to press it twice.
    func retryReading() {
        speaker.stop()
        startReading()
        speaker.resume()
    }

    /// Where the page should follow: the verse being said while the voice is sounding, and only
    /// then. Paused or ready has no claim on where the reader is looking. The Mac's
    /// `Listen::following`.
    var followingVoice: VoicePosition? {
        guard speaker.phase == .reading, let chapter = speaker.chapter, let verse = speaker.speaking
        else { return nil }
        return VoicePosition(chapter: chapter, verse: Int(verse))
    }

    /// The verse Read Aloud is saying, when it is saying one on the chapter on screen.
    var speakingVerse: Int? {
        guard speaker.phase.isOn, speaker.chapter == position.chapter,
            let verse = speaker.speaking
        else { return nil }
        return Int(verse)
    }

    /// A word held down on the page: its card explains it. Nothing else changes — the reading
    /// carries on and the page stays exactly where it is.
    func lookUp(word: String, chapter: Int, verse: Int) {
        let ref = ref(chapter: chapter, verse: verse)
        sheet = .lookup(
            WordLookup(
                word: word, chapter: chapter, verse: verse,
                reference: rangeLabel(from: ref, to: ref)))
    }

    /// The voice follows the page: anything that moves the reader ends the reading.
    func stopReading() {
        if speaker.phase.isOn { speaker.stop() }
    }

    // MARK: - Beside the text

    /// Are there related verses for this one? Asked before the bar offers the row, so a reader is
    /// never sent to an empty card.
    func hasRelated(_ ref: VerseRef) -> Bool {
        (try? relatedHas(at: ref)) ?? false
    }

    /// The verses the tradition links to this one, best-voted first.
    func related(_ ref: VerseRef) -> [RelatedLink] {
        (try? relatedVerses(at: ref)) ?? []
    }

    /// How to credit the cross references, for the foot of the card.
    var relatedCreditLine: String { relatedCredit() }

    /// Is there original text for this verse? Said the same way the Mac says it: only offer the
    /// row when there is something behind it.
    func hasOriginal(_ ref: VerseRef) -> Bool {
        (try? originalHas(at: ref)) ?? false
    }

    /// The verse's words in the language it was written in.
    func original(_ ref: VerseRef) -> OriginalVerse? {
        (try? originalVerse(at: ref)) ?? nil
    }

    /// The dictionary entry behind a Strong's number, four digits zero-padded.
    func entry(_ strong: String) -> LexiconEntry? {
        (try? lexiconEntry(strong: strong)) ?? nil
    }

    /// How to credit the original-language text and lexicon.
    var wordsCreditLine: String { originalCredit() }

    /// The verse a selection sheet should speak about: the first one tapped.
    var selectionRef: VerseRef? { selectedRefs.first }

    func export(_ format: ExportFormat) -> String? {
        try? bible.export(format: format, translation: settings.translation)
    }

    @discardableResult
    private func study(_ change: () throws -> Void) -> Bool {
        defer { marksVersion += 1 }
        do {
            try change()
            return true
        } catch {
            show("Couldn’t save: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Toasts

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    // MARK: Saving

    private struct Saved: Codable {
        var settings: ReaderSettings?
        var chapter: Int?
        var verse: Int?
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        saveTask?.cancel()
        let saved = Saved(settings: settings, chapter: position.chapter, verse: position.verse)
        guard let data = try? JSONEncoder().encode(saved), let json = String(data: data, encoding: .utf8) else { return }
        try? bible.setSetting(key: "ios", value: json)
    }
}

enum Log {
    static let app = Logger(subsystem: "au.com.onyxit.lamplit.dev", category: "app")
}

/// Time since the process started, for launch measurements.
enum LaunchClock {
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let t = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000)
    }()

    private static var logged = Set<String>()

    static func mark(_ event: String) {
        guard !logged.contains(event) else { return }
        logged.insert(event)
        let ms = Date().timeIntervalSince(processStart) * 1000
        Log.app.notice("\(event, privacy: .public): \(ms, format: .fixed(precision: 0), privacy: .public) ms after launch")
    }
}
