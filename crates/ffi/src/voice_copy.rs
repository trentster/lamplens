//! The voice-download wording, handed to Swift so the phone and the Mac say the same thing.
//!
//! The strings live in `bible_core::voice_copy`; this is only the door they come through.

use bible_core::voice_copy as copy;

/// What the download is, and what it buys.
#[uniffi::export]
pub fn voice_download_main() -> String {
    copy::VOICE_DOWNLOAD_MAIN.to_string()
}

/// The line below it.
#[uniffi::export]
pub fn voice_download_second() -> String {
    copy::VOICE_DOWNLOAD_SECOND.to_string()
}

/// The button that starts it.
#[uniffi::export]
pub fn voice_download_button() -> String {
    copy::VOICE_DOWNLOAD_BUTTON.to_string()
}

#[cfg(test)]
mod tests {
    /// The door returns the core's words, not a copy of them.
    #[test]
    fn the_door_and_the_core_agree() {
        assert_eq!(super::voice_download_main(), bible_core::voice_copy::VOICE_DOWNLOAD_MAIN);
    }
}
