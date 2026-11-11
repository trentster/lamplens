//! Who made what the app carries, and under what terms — the same list the Mac's About panel
//! shows, read from `bible_core::credits` so the two can never say different things.
//!
//! The App Store asks for a licence record, and three of these works are CC BY: the credit is not a
//! courtesy, it is the licence condition.

use bible_core::credits as core_credits;

/// One work the app carries: what it is, who holds it, its licence, and where it came from.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct CreditRow {
    pub work: String,
    pub holder: String,
    pub licence: String,
    pub url: String,
    /// How it is used here, in one line. Empty when the work's name says it.
    pub note: String,
}

/// Everything the app carries that someone else made, in the order a reader would look for it.
#[uniffi::export]
pub fn credits() -> Vec<CreditRow> {
    core_credits::all()
        .iter()
        .map(|c| CreditRow {
            work: c.work.to_string(),
            holder: c.holder.to_string(),
            licence: c.licence.to_string(),
            url: c.url.to_string(),
            note: c.note.to_string(),
        })
        .collect()
}

/// The sign-off under the list: who made this app, and what it is built on.
#[uniffi::export]
pub fn credits_signoff() -> String {
    "Lamplens, by Mark Trent. Based on bible-rs, MIT License.".to_string()
}

/// The Ark's credit line, verbatim from the repository's own note, for wherever it is shown.
#[uniffi::export]
pub fn ark_credit() -> String {
    core_credits::ARK_CREDIT.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_credit_carries_its_holder_and_licence() {
        let rows = credits();
        assert!(rows.len() >= 6, "only {} credits came through", rows.len());
        for row in &rows {
            assert!(!row.work.is_empty(), "a credit with no work named");
            assert!(!row.holder.is_empty(), "{} names no holder", row.work);
            assert!(!row.licence.is_empty(), "{} names no licence", row.work);
        }
    }

    /// The CC BY works are the ones a reader must be able to trace, so their terms come through.
    #[test]
    fn the_cc_by_works_are_credited_by_name() {
        let rows = credits();
        for wanted in ["STEPBible", "OpenBible", "WordNet"] {
            let found = rows.iter().find(|r| r.work.contains(wanted));
            let row = found.unwrap_or_else(|| panic!("{wanted} is carried but not credited"));
            assert!(row.licence.contains("CC BY"), "{} is not under CC BY: {}", row.work, row.licence);
            assert!(row.url.starts_with("http"), "{} has no source: {}", row.work, row.url);
        }
    }

    #[test]
    fn the_signoff_names_the_app_and_its_foundation() {
        let sign = credits_signoff();
        assert!(sign.contains("Lamplens"));
        assert!(sign.contains("MIT"));
        assert!(ark_credit().contains("CC BY 4.0"));
    }
}
