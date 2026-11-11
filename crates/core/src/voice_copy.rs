//! The words for the one time Lamplens uses the network.
//!
//! The voice download is a product promise, not a layout detail: it is the only connection the app
//! ever makes, and what it buys — reading aloud with the radio off — is the point of it. Written
//! once here rather than twice in two languages, where the two copies would drift apart.

/// What the download is, and what it buys.
pub const VOICE_DOWNLOAD_MAIN: &str = "A one-time 66 MB download lets Lamplens read aloud offline.";

/// Why that is the whole story.
pub const VOICE_DOWNLOAD_SECOND: &str = "Nothing else in Lamplens uses the internet.";

/// The control that starts it.
pub const VOICE_DOWNLOAD_BUTTON: &str = "Download the voice";

#[cfg(test)]
mod tests {
    use super::*;

    /// A size in the copy that disagrees with the download is the kind of small untruth that makes
    /// everything else in the app doubtful, so the number is checked against the pinned bundle.
    #[test]
    fn the_stated_size_is_the_size_that_gets_fetched() {
        let stated: u64 = VOICE_DOWNLOAD_MAIN
            .split_whitespace()
            .find_map(|word| word.parse::<u64>().ok())
            .expect("the main line states a size in megabytes");
        assert_eq!(crate::speak::bundle::TOTAL_BYTES / 1_000_000, stated);
    }

    /// One fact each: what it costs, then what it means. Neither line repeats the other.
    #[test]
    fn the_lines_carry_different_facts() {
        assert!(VOICE_DOWNLOAD_MAIN.contains("one-time") && VOICE_DOWNLOAD_MAIN.contains("offline"));
        assert!(!VOICE_DOWNLOAD_SECOND.contains("offline"));
        assert!(VOICE_DOWNLOAD_SECOND.contains("internet"));
        assert!(!VOICE_DOWNLOAD_BUTTON.is_empty());
    }
}
