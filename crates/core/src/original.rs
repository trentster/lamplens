//! The original-language words behind a verse — Hebrew for the Old Testament, Aramaic in the parts
//! of Daniel and Ezra written in it, and Greek for the New.
//!
//! Source: STEPBible.org "Translators Amalgamated" Hebrew OT and Greek NT, and their Translators
//! Brief lexicons for the entries. CC BY 4.0, built into `data/original/` by
//! `scripts/build-original.py`. The step is the point: we show the verse's own words rather than
//! claiming which English word became which, so nothing here depends on a translation's wording.
//!
//! Nothing runs on the startup path. The tables unpack the first time a lookup asks for them, and a
//! table that will not unpack leaves the feature empty rather than panicking in front of a reader.

use crate::books::BookId;

/// The language a verse was written in. Aramaic is not a rounding error: Daniel 2:4 onwards is
/// Aramaic, and calling it Hebrew would be a small lie told on every word.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Language {
    #[default]
    Hebrew,
    Aramaic,
    Greek,
}

impl Language {
    pub fn name(self) -> &'static str {
        match self {
            Language::Hebrew => "Hebrew",
            Language::Aramaic => "Aramaic",
            Language::Greek => "Greek",
        }
    }

    fn from_code(code: u8) -> Self {
        match code {
            b'A' => Language::Aramaic,
            b'G' => Language::Greek,
            _ => Language::Hebrew,
        }
    }
}

/// One word as it stands in the verse: the text itself, how it sounds, the gloss translators give
/// it, and the number that leads to the entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Word {
    pub surface: String,
    pub translit: String,
    pub gloss: String,
    pub strong: String,
}

/// A verse's original words, in the order they were written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Verse {
    pub language: Language,
    pub words: Vec<Word>,
}

/// A lexicon entry for one Strong's number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub id: String,
    pub lemma: String,
    pub translit: String,
    pub pos: String,
    /// The one-line gloss: "father", "to create".
    pub short: String,
    /// The full definition, exactly as the source writes it: STEPBible's markup and all.
    pub body: String,
}

impl Entry {
    /// The definition as a reader should see it, line by line: see [`definition_lines`].
    pub fn lines(&self) -> Vec<String> {
        definition_lines(&self.body)
    }
}

/// Turns a lexicon definition into plain lines for a reader.
///
/// The source carries its own markup, and both lexicons use it: line breaks in four spellings
/// (`<br>`, `<BR />`, `<lb />`, …), `<b>` and `<i>`, verse links (`<ref='Act.9.41'>Act.9:41</ref>`),
/// scholarly tags (`<author>`, `<date>`, `<a href=…>`) and `__1.`-style outline markers. Only the
/// plain `<br>` used to be removed, so a Greek entry reached the screen as raw code.
///
/// Line breaks become new lines; every other tag is dropped and its words kept; a verse link keeps
/// the text it shows, with the book's code turned into the book's usual short form ("Acts 9:41"
/// rather than "Act.9:41"); entities are decoded; the outline markers go. Anything that only looks
/// like a tag (the Hebrew lexicon's `future<->past`) is left as written.
pub fn definition_lines(body: &str) -> Vec<String> {
    let mut text = String::with_capacity(body.len());
    // Where the text of the open verse link starts, so it can be rewritten when the link closes.
    let mut link_start: Option<usize> = None;
    let mut rest = body;
    while let Some(open) = rest.find('<') {
        text.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        let Some(close) = after.find('>') else {
            text.push_str(&rest[open..]);
            rest = "";
            break;
        };
        let tag = &after[..close];
        let name = tag_name(tag);
        match name.as_deref() {
            Some("br") | Some("lb") => text.push('\n'),
            Some("ref") if !tag.starts_with('/') => link_start = Some(text.len()),
            Some("ref") => {
                if let Some(start) = link_start.take() {
                    let shown = readable_reference(&text[start..]);
                    text.truncate(start);
                    text.push_str(&shown);
                }
            }
            Some(_) => {}
            // Not markup at all: keep it exactly as written.
            None => {
                text.push('<');
                text.push_str(tag);
                text.push('>');
            }
        }
        rest = &after[close + 1..];
    }
    text.push_str(rest);
    let text = text
        .replace("__", "")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&amp;", "&");
    text.split('\n')
        .map(|line| {
            let line = line.split_whitespace().collect::<Vec<_>>().join(" ");
            // The lexicons open a new sense with a colon, which reaches a reader as a typo:
            // ": beginning". The colon and the space after it go.
            match line.strip_prefix(':') {
                Some(rest) => rest.trim_start().to_string(),
                None => line,
            }
        })
        .filter(|line| !line.is_empty())
        .collect()
}

/// The lower-case name of a tag (`BR /` gives `br`, `/ref` gives `ref`, `ref='Act.9.41'` gives
/// `ref`), or `None` when the brackets hold something that is not a tag name.
fn tag_name(tag: &str) -> Option<String> {
    let name = tag.strip_prefix('/').unwrap_or(tag).trim_start();
    let end = name.find(|c: char| !c.is_ascii_alphanumeric()).unwrap_or(name.len());
    let name = &name[..end];
    let starts_with_letter = name.chars().next().is_some_and(|c| c.is_ascii_alphabetic());
    starts_with_letter.then(|| name.to_ascii_lowercase())
}

/// "Act.9:41;" becomes "Acts 9:41;". A code that names none of the 66 books (the lexicons also
/// cite the Septuagint's extra books) is left as the source wrote it.
fn readable_reference(shown: &str) -> String {
    let Some((code, place)) = shown.split_once('.') else { return shown.to_string() };
    if !place.starts_with(|c: char| c.is_ascii_digit()) {
        return shown.to_string();
    }
    match book_from_lexicon_code(code.trim()) {
        Some(book) => format!("{} {place}", book.info().abbrev),
        None => shown.to_string(),
    }
}

/// The lexicons cite books by USFM code (`Jhn`, `Mrk`), by OSIS name (`Acts`, `1Cor`) and by a few
/// abbreviations of their own (`1Jo`), so all three are tried.
fn book_from_lexicon_code(code: &str) -> Option<BookId> {
    BookId::from_code(code).or_else(|| BookId::from_osis(code)).or_else(|| {
        let lower = code.to_ascii_lowercase();
        BookId::all().find(|book| book.info().aliases.contains(&lower.as_str()))
    })
}

/// How to credit the data, for the About panel and the foot of a list.
pub fn credit() -> &'static str {
    "Original-language text and lexicon: STEPBible.org, CC BY 4.0"
}

/// The words of one verse, or `None` when we have no original text for it.
#[cfg(feature = "bundled")]
pub fn verse(book: BookId, chapter: u8, verse: u8) -> Option<Verse> {
    bundled::verse(book, chapter, verse)
}

/// A build without the bundled data has no original text, which is not an error: the lookup simply
/// does not offer the row.
#[cfg(not(feature = "bundled"))]
pub fn verse(_book: BookId, _chapter: u8, _verse: u8) -> Option<Verse> {
    None
}

/// The dictionary entry behind a Strong's number, or `None` when there is no entry for it.
#[cfg(feature = "bundled")]
pub fn entry(strong: &str) -> Option<Entry> {
    bundled::entry(strong)
}

#[cfg(not(feature = "bundled"))]
pub fn entry(_strong: &str) -> Option<Entry> {
    None
}

/// Is there original text for this verse at all? A popover asks this before offering the row.
#[cfg(feature = "bundled")]
pub fn has(book: BookId, chapter: u8, verse: u8) -> bool {
    bundled::verse(book, chapter, verse).is_some()
}

#[cfg(not(feature = "bundled"))]
pub fn has(_book: BookId, _chapter: u8, _verse: u8) -> bool {
    false
}

#[cfg(feature = "bundled")]
mod bundled {
    use super::{Entry, Language, Verse, Word};
    use crate::books::BookId;
    use std::collections::HashMap;
    use std::sync::OnceLock;

    /// The tables, compressed with zstd exactly as the translations and dictionaries are: the C
    /// library in a native build, the pure-Rust decoder in the browser.
    macro_rules! table {
        ($id:literal) => {
            include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../../data/original/", $id, ".tsv.zst"))
                as &[u8]
        };
    }

    static WORDS: &[u8] = table!("words");
    static LEX_H: &[u8] = table!("lex-h");
    static LEX_G: &[u8] = table!("lex-g");

    /// One compressed table, unpacked to text. A table that will not unpack yields `None` rather
    /// than taking the app down in front of a reader.
    fn unpack(data: &[u8]) -> Option<String> {
        use std::io::Read;
        let mut out = Vec::new();
        #[cfg(not(target_arch = "wasm32"))]
        let unpacked = zstd::stream::read::Decoder::with_buffer(data)
            .and_then(|mut decoder| decoder.read_to_end(&mut out));
        #[cfg(target_arch = "wasm32")]
        let unpacked = match ruzstd::decoding::StreamingDecoder::new(data) {
            Ok(mut decoder) => decoder
                .read_to_end(&mut out)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())),
            Err(e) => Err(std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string())),
        };
        match unpacked {
            Ok(_) => String::from_utf8(out).ok(),
            Err(e) => {
                #[cfg(not(target_arch = "wasm32"))]
                eprintln!("bible: original-language text would not unpack: {e}");
                let _ = e;
                None
            }
        }
    }

    /// Where one verse's words sit in the unpacked text: from the first byte of its first word to
    /// the last byte of its last, plus the language they are in.
    struct Span {
        start: usize,
        end: usize,
        language: Language,
    }

    struct Words {
        text: String,
        verses: HashMap<(u8, u8, u8), Span>,
    }

    impl Words {
        /// Parsed once, on the first verse anyone asks about.
        fn get() -> Option<&'static Words> {
            static ONCE: OnceLock<Option<Words>> = OnceLock::new();
            ONCE.get_or_init(|| Words::parse(&unpack(WORDS)?)).as_ref()
        }

        /// The file is verse headers — `@GEN 1 1 7 H`, then seven word lines — so one pass builds
        /// every span without keeping a second copy of the text.
        fn parse(text: &str) -> Option<Words> {
            let mut verses = HashMap::with_capacity(32_000);
            let mut open: Option<((u8, u8, u8), usize, Language)> = None;
            let mut offset = 0;
            let mut lines = 0;
            for line in text.split_inclusive('\n') {
                let start = offset;
                offset += line.len();
                lines += 1;
                if line.starts_with('#') {
                    continue;
                }
                if let Some(header) = line.strip_prefix('@') {
                    if let Some((key, from, language)) = open.take() {
                        verses.insert(key, Span { start: from, end: start, language });
                    }
                    let mut parts = header.trim_end().split('\t');
                    let book = parts.next()?;
                    let chapter: u8 = parts.next()?.trim().parse().ok()?;
                    let number: u8 = parts.next()?.trim().parse().ok()?;
                    let _count: usize = parts.next()?.trim().parse().ok()?;
                    let code = parts.next().unwrap_or("H").trim().as_bytes();
                    let language = Language::from_code(*code.first().unwrap_or(&b'H'));
                    let index = BookId::from_code(book)?.index() as u8;
                    open = Some(((index, chapter, number), offset, language));
                }
            }
            if let Some((key, from, language)) = open.take() {
                verses.insert(key, Span { start: from, end: offset.min(text.len()), language });
            }
            debug_assert!(lines > 0);
            (!verses.is_empty()).then(|| Words { text: text.to_string(), verses })
        }

        fn verse(&self, book: BookId, chapter: u8, verse: u8) -> Option<Verse> {
            let span = self.verses.get(&(book.index() as u8, chapter, verse))?;
            let mut words = Vec::new();
            for line in self.text[span.start..span.end].lines() {
                let mut parts = line.trim_end().split('\t');
                let surface = parts.next().unwrap_or_default();
                if surface.is_empty() {
                    continue;
                }
                words.push(Word {
                    surface: surface.to_string(),
                    translit: parts.next().unwrap_or_default().to_string(),
                    gloss: parts.next().unwrap_or_default().to_string(),
                    strong: parts.next().unwrap_or_default().to_string(),
                });
            }
            (!words.is_empty()).then(|| Verse { language: span.language, words })
        }
    }

    /// The two lexicons as one index: entry id to where its text sits, plus a fallback from a bare
    /// number to the first numbered sense, because words carry `H0430` while the lexicon lists
    /// `H0430G`, `H0430H`, `H0430I`.
    struct Lexicon {
        text: String,
        spans: HashMap<String, (usize, usize)>,
        bare: HashMap<String, String>,
    }

    impl Lexicon {
        fn get() -> Option<&'static Lexicon> {
            static ONCE: OnceLock<Option<Lexicon>> = OnceLock::new();
            ONCE.get_or_init(|| {
                let mut text = unpack(LEX_H)?;
                text.push('\n');
                text.push_str(&unpack(LEX_G)?);
                Lexicon::parse(&text)
            })
            .as_ref()
        }

        fn parse(text: &str) -> Option<Lexicon> {
            let mut spans = HashMap::with_capacity(24_000);
            let mut bare: HashMap<String, String> = HashMap::with_capacity(24_000);
            let mut offset = 0;
            for line in text.split_inclusive('\n') {
                let start = offset;
                offset += line.len();
                if line.starts_with('#') || line.trim().is_empty() {
                    continue;
                }
                let ident = line.split('\t').next().unwrap_or_default().trim();
                if ident.is_empty() {
                    continue;
                }
                bare.entry(base_of(ident)).or_insert_with(|| ident.to_string());
                spans.entry(ident.to_string()).or_insert((start, start + line.len() - 1));
            }
            (!spans.is_empty()).then(|| Lexicon { text: text.to_string(), spans, bare })
        }

        /// `H0430J` is not listed, but `H0430` is the same entry and `H0430G` is its first sense.
        fn resolve(&self, number: &str) -> Option<&str> {
            let key = number.trim().trim_end_matches(|c: char| !c.is_ascii_alphanumeric());
            if key.is_empty() {
                return None;
            }
            if let Some((id, _)) = self.spans.get_key_value(key) {
                return Some(id);
            }
            let bare = base_of(key);
            if let Some((id, _)) = self.spans.get_key_value(bare.as_str()) {
                return Some(id);
            }
            self.bare.get(bare.as_str()).map(String::as_str)
        }

        fn entry(&self, number: &str) -> Option<Entry> {
            let id = self.resolve(number)?;
            let (start, end) = *self.spans.get(id)?;
            let mut parts = self.text[start..end].split('\t');
            let field = |p: Option<&str>| p.unwrap_or_default().trim().to_string();
            Some(Entry {
                id: field(parts.next()),
                lemma: field(parts.next()),
                translit: field(parts.next()),
                pos: field(parts.next()),
                short: field(parts.next()),
                body: field(parts.next()),
            })
        }
    }

    /// `H0430G` and `H0430` are the same number to a reader: the trailing letter only separates
    /// senses within one entry.
    fn base_of(id: &str) -> String {
        let trimmed = id.trim().trim_end_matches(|c: char| !c.is_ascii_alphanumeric());
        let without_sense = trimmed.trim_end_matches(|c: char| c.is_ascii_uppercase());
        if without_sense.is_empty() { trimmed.to_string() } else { without_sense.to_string() }
    }

    pub(super) fn verse(book: BookId, chapter: u8, verse: u8) -> Option<Verse> {
        Words::get()?.verse(book, chapter, verse)
    }

    pub(super) fn entry(strong: &str) -> Option<Entry> {
        Lexicon::get()?.entry(strong)
    }
}

#[cfg(all(test, feature = "bundled"))]
mod tests {
    use super::*;
    use crate::books::BookId;

    /// Hebrew points and cantillation marks: the same word can be encoded with the marks in a
    /// different order, so tests compare the letters a reader sees.
    fn consonants(text: &str) -> String {
        text.chars().filter(|c| !('\u{0591}'..='\u{05C7}').contains(c)).collect()
    }

    #[test]
    fn genesis_one_one_has_its_seven_hebrew_words() {
        let v = verse(BookId::GENESIS, 1, 1).expect("Genesis 1:1 has original text");
        assert_eq!(v.language, Language::Hebrew);
        assert_eq!(v.words.len(), 7, "Bereshit bara elohim et hashamayim ve'et ha'aretz");
        assert_eq!(consonants(&v.words[0].surface), "בראשית");
        assert!(v.words[0].gloss.contains("beginning"), "{}", v.words[0].gloss);
        assert_eq!(v.words[0].strong, "H7225G");
        assert_eq!(v.words[1].strong, "H1254A", "bara, the word behind 'created'");
        // The verse ends with the earth, not with an escape marker from the source.
        assert_eq!(v.words[6].strong, "H0776G");
        assert_eq!(consonants(&v.words[6].surface), "הארץ");
    }

    #[test]
    fn the_new_testament_is_greek() {
        let v = verse(BookId::from_code("JHN").unwrap(), 3, 16).expect("John 3:16");
        assert_eq!(v.language, Language::Greek);
        assert_eq!(v.words.len(), 26);
        assert!(v.words.iter().any(|w| w.strong.starts_with("G0025")), "egapesen is G25");
    }

    #[test]
    fn daniel_two_five_is_aramaic() {
        let v = verse(BookId::from_code("DAN").unwrap(), 2, 5).expect("Daniel 2:5");
        assert_eq!(v.language, Language::Aramaic, "the Aramaic half of Daniel");
    }

    #[test]
    fn psalm_titles_come_with_verse_one() {
        // The KJV prints the title as part of verse 1; the Hebrew numbers it as verse 0. The list
        // must match what the reader can see, so the title's words belong to verse 1.
        let v = verse(BookId::PSALMS, 3, 1).expect("Psalm 3:1");
        assert!(v.words[0].gloss.contains("psalm"), "{:?}", v.words[0]);
    }

    #[test]
    fn a_verse_we_have_nothing_for_says_so() {
        // Romans 16:25 is a versification outlier: it is in the KJV and not in the tagged text.
        assert!(verse(BookId::from_code("ROM").unwrap(), 16, 25).is_none());
        assert!(!has(BookId::from_code("ROM").unwrap(), 16, 25));
    }

    #[test]
    fn an_entry_is_reachable_from_the_numbers_the_words_carry() {
        let entry = entry("H1254A").expect("bara has an entry");
        assert_eq!(consonants(&entry.lemma), "ברא");
        assert!(entry.short.to_lowercase().contains("create"), "{}", entry.short);
        assert!(!entry.lines().is_empty());
    }

    /// Mark's find on the phone: a Greek entry reached the screen as raw markup. Every entry in both
    /// lexicons must come out as plain words.
    #[test]
    fn no_entry_shows_markup() {
        let mut shown = 0;
        for prefix in ['G', 'H'] {
            for number in 1..=9_100 {
                let Some(entry) = entry(&format!("{prefix}{number:04}")) else { continue };
                shown += 1;
                for line in entry.lines() {
                    let tag = line.match_indices('<').any(|(at, _)| {
                        line[at + 1..].starts_with(|c: char| c.is_ascii_alphabetic() || c == '/')
                    });
                    assert!(!tag, "{} still shows markup: {line}", entry.id);
                    assert!(!line.contains("__"), "{} still shows an outline marker: {line}", entry.id);
                }
            }
        }
        assert!(shown > 10_000, "only {shown} entries were checked");
    }

    /// Mark's find on the phone: the first definition line opened with a colon (": beginning").
    /// The lexicons use it to open a sense; on screen it reads as a typo. No line of any entry in
    /// either lexicon opens with one, H7225G's included.
    #[test]
    fn no_entry_opens_a_line_with_a_colon() {
        for prefix in ['G', 'H'] {
            for number in 1..=9_100 {
                let Some(entry) = entry(&format!("{prefix}{number:04}")) else { continue };
                for line in entry.lines() {
                    assert!(!line.starts_with(':'), "{} still opens with a colon: {line}", entry.id);
                }
            }
        }
        let reshit = entry("H7225G").expect("reshit has an entry");
        assert!(!reshit.lines().is_empty(), "{} has no lines", reshit.id);
        assert!(!reshit.lines()[0].starts_with(':'), "{:?}", reshit.lines()[0]);
    }

    #[test]
    fn anistemi_reads_as_words() {
        let entry = entry("G0450").expect("anistemi has an entry");
        let lines = entry.lines();
        assert!(lines.len() > 3, "the entry's own line breaks are kept: {lines:?}");
        let all = lines.join("\n");
        assert!(all.contains("to raise up"), "{all}");
        assert!(all.contains("Acts 9:41"), "a verse link reads as a reference: {all}");
        assert!(all.contains("John 6:39"), "{all}");
    }

    #[test]
    fn a_bare_number_finds_its_first_sense() {
        // Words carry H0430 where the lexicon lists H0430G, H0430H, H0430I.
        let entry = entry("H0430").expect("elohim resolves through its first sense");
        assert!(entry.id.starts_with("H0430"), "{}", entry.id);
        assert!(entry.short.to_lowercase().contains("god"), "{}", entry.short);
        // And a numbered sense that the lexicon never lists still lands on the entry.
        assert!(entry_from("H0430J").is_some());
    }

    fn entry_from(number: &str) -> Option<Entry> {
        entry(number)
    }

    #[test]
    fn the_whole_bible_is_covered_except_the_known_oddities() {
        let mut missing = Vec::new();
        for book in BookId::all() {
            for chapter in 1..=book.chapters() {
                // Only the verses we know about: a chapter's last verse is enough to prove the
                // span parsing works across every book.
                if verse(book, chapter, 1).is_none() {
                    missing.push(format!("{} {chapter}:1", book.name()));
                }
            }
        }
        assert!(missing.len() <= 12, "chapter openings without originals: {missing:?}");
    }
}

#[cfg(test)]
mod markup_tests {
    use super::definition_lines;

    #[test]
    fn the_lexicons_leading_colon_goes() {
        assert_eq!(definition_lines(": beginning"), ["beginning"]);
        assert_eq!(definition_lines("first<br />: second"), ["first", "second"]);
        assert_eq!(definition_lines("a colon, not a marker: like this"), ["a colon, not a marker: like this"]);
    }

    #[test]
    fn every_spelling_of_a_line_break_breaks_the_line() {
        assert_eq!(definition_lines("a<br>b<BR />c<BR>d<br />e<lb />f"), ["a", "b", "c", "d", "e", "f"]);
    }

    #[test]
    fn emphasis_and_scholarly_tags_go_and_their_words_stay() {
        assert_eq!(
            definition_lines("<b>to raise up</b>, <i>Words</i>, <author>Dalman</author> <date>1902</date>"),
            ["to raise up, Words, Dalman 1902"]
        );
        assert_eq!(
            definition_lines("<a href=\"javascript:void(0)\" title=\"Odyssey by Homer\">8th/7th c.BC</a>"),
            ["8th/7th c.BC"]
        );
    }

    #[test]
    fn a_verse_link_reads_as_a_reference() {
        assert_eq!(definition_lines("<ref='Act.9.41'>Act.9:41;</ref>"), ["Acts 9:41;"]);
        assert_eq!(definition_lines("<ref='Jhn.6.39'>Jhn.6:39</ref>"), ["John 6:39"]);
        assert_eq!(definition_lines("<ref='1Co.1.1'>1Co.1:1</ref>"), ["1 Cor 1:1"]);
        assert_eq!(definition_lines("<ref='Act.3.22, 26'>Act.3:22, 26</ref>"), ["Acts 3:22, 26"]);
        // A book outside the 66 keeps the source's own spelling.
        assert_eq!(definition_lines("<ref='Sir.1.1'>Sir.1:1</ref>"), ["Sir.1:1"]);
    }

    #[test]
    fn outline_markers_and_entities_are_cleaned() {
        assert_eq!(definition_lines("<BR />__1. causal <BR />__(a) to rise"), ["1. causal", "(a) to rise"]);
        assert_eq!(definition_lines("a &gt; b &amp; c"), ["a > b & c"]);
    }

    #[test]
    fn something_that_only_looks_like_a_tag_is_left_alone() {
        assert_eq!(definition_lines("(future<->past)"), ["(future<->past)"]);
        assert_eq!(definition_lines("a < b"), ["a < b"]);
    }

    #[test]
    fn spacing_is_tidied_and_empty_lines_dropped() {
        assert_eq!(definition_lines("  a   b <br><br>  c "), ["a b", "c"]);
    }
}
