//! Input validation helpers.

/// Validate that a string represents a valid, non-negative decimal amount.
pub fn validate_amount(s: &str) -> Result<(), &'static str> {
    if s.is_empty() {
        return Err("empty amount");
    }
    let parsed: f64 = s.parse().map_err(|_| "invalid number")?;
    if parsed < 0.0 {
        return Err("negative amount");
    }
    if parsed.is_nan() || parsed.is_infinite() {
        return Err("invalid amount");
    }
    Ok(())
}
