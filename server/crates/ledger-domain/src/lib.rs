use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Money {
    pub amount_minor: i128,
    pub currency: String,
}

impl Money {
    pub fn new(amount_minor: i128, currency: impl Into<String>) -> Result<Self, DomainError> {
        if amount_minor == 0 {
            return Err(DomainError::ZeroAmount);
        }
        let currency = currency.into();
        if currency.len() != 3 || !currency.chars().all(|c| c.is_ascii_uppercase()) {
            return Err(DomainError::InvalidCurrency);
        }
        if amount_minor < i64::MIN as i128 || amount_minor > i64::MAX as i128 {
            return Err(DomainError::AmountOutOfRange);
        }
        Ok(Self {
            amount_minor,
            currency,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EntryDraft {
    pub account_id: String,
    pub amount_minor: i128,
    pub currency: String,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DomainError {
    #[error("amount must be non-zero")]
    ZeroAmount,
    #[error("invalid currency")]
    InvalidCurrency,
    #[error("amount out of BIGINT range")]
    AmountOutOfRange,
    #[error("transaction requires at least two entries")]
    TooFewEntries,
    #[error("entries are unbalanced")]
    Unbalanced,
    #[error("currency mismatch")]
    CurrencyMismatch,
}

pub fn validate_balanced(entries: &[EntryDraft]) -> Result<(), DomainError> {
    if entries.len() < 2 {
        return Err(DomainError::TooFewEntries);
    }
    let currency = &entries[0].currency;
    let mut sum: i128 = 0;
    for e in entries {
        if &e.currency != currency {
            return Err(DomainError::CurrencyMismatch);
        }
        Money::new(e.amount_minor, e.currency.clone())?;
        sum += e.amount_minor;
    }
    if sum != 0 {
        return Err(DomainError::Unbalanced);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn balanced_ok() {
        let entries = vec![
            EntryDraft {
                account_id: "a".into(),
                amount_minor: 100,
                currency: "CNY".into(),
            },
            EntryDraft {
                account_id: "b".into(),
                amount_minor: -100,
                currency: "CNY".into(),
            },
        ];
        assert!(validate_balanced(&entries).is_ok());
    }

    #[test]
    fn unbalanced_rejected() {
        let entries = vec![
            EntryDraft {
                account_id: "a".into(),
                amount_minor: 100,
                currency: "CNY".into(),
            },
            EntryDraft {
                account_id: "b".into(),
                amount_minor: -50,
                currency: "CNY".into(),
            },
        ];
        assert_eq!(validate_balanced(&entries), Err(DomainError::Unbalanced));
    }
}
