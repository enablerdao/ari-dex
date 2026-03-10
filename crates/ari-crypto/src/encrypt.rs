//! Intent encryption and decryption for MEV protection.
//!
//! Provides high-level functions to encrypt/decrypt [`Intent`] values using
//! the threshold encryption scheme from [`crate::threshold`].

use ari_core::Intent;

use crate::threshold::{self, Ciphertext, DecryptionShare, KeyShare};

/// An encrypted intent payload ready for submission to the mempool.
#[derive(Debug, Clone)]
pub struct EncryptedIntent {
    /// The threshold-encrypted ciphertext.
    pub ciphertext: Ciphertext,
}

/// Encrypt an intent using the threshold encryption key.
///
/// The intent is serialised to JSON then encrypted with AES-256-GCM using
/// the provided encryption key.
pub fn encrypt_intent(intent: &Intent, encryption_key: &[u8]) -> EncryptedIntent {
    let serialised =
        serde_json::to_vec(intent).expect("Intent serialisation should not fail");
    let ciphertext = threshold::encrypt(&serialised, encryption_key);
    EncryptedIntent { ciphertext }
}

/// Decrypt an encrypted intent by combining decryption shares.
///
/// Requires at least `threshold` shares to reconstruct the AES key and
/// decrypt the ciphertext.
pub fn decrypt_intent(
    encrypted: &EncryptedIntent,
    shares: &[DecryptionShare],
    threshold: u32,
) -> ari_core::Result<Intent> {
    let plaintext = threshold::combine_shares(&encrypted.ciphertext, shares, threshold)
        .ok_or_else(|| {
            ari_core::AriError::InternalError(
                "failed to combine decryption shares".into(),
            )
        })?;

    serde_json::from_slice(&plaintext).map_err(|e| {
        ari_core::AriError::InternalError(format!("failed to deserialise intent: {e}"))
    })
}

/// Helper: produce decryption shares from key shares (delegates to threshold module).
pub fn make_decryption_shares(
    ciphertext: &Ciphertext,
    key_shares: &[KeyShare],
) -> Vec<DecryptionShare> {
    key_shares
        .iter()
        .map(|ks| threshold::decrypt_share(ciphertext, ks))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::threshold::ThresholdKeySet;
    use ari_core::*;

    fn make_test_intent() -> Intent {
        let token = Token {
            chain: ChainId::Ethereum,
            address: [0u8; 20],
            symbol: "WETH".into(),
            decimals: 18,
        };
        Intent {
            sender: [1u8; 20],
            sell_token: token.clone(),
            buy_token: Token {
                symbol: "USDC".into(),
                address: [2u8; 20],
                ..token
            },
            sell_amount: [0u8; 32],
            buy_amount: [0u8; 32],
            min_buy: [0u8; 32],
            deadline: u64::MAX,
            src_chain: ChainId::Ethereum,
            dst_chain: None,
            partial_fill: false,
            nonce: 42,
            signature: [0u8; 65],
        }
    }

    #[test]
    fn test_encrypt_decrypt_intent_roundtrip() {
        let intent = make_test_intent();
        let ks = ThresholdKeySet::generate(2, 3);

        let encrypted = encrypt_intent(&intent, &ks.encryption_key);

        // Produce decryption shares from 2 of 3 key shares.
        let dec_shares = make_decryption_shares(&encrypted.ciphertext, &ks.shares[..2]);

        let recovered = decrypt_intent(&encrypted, &dec_shares, 2).unwrap();
        assert_eq!(recovered.nonce, intent.nonce);
        assert_eq!(recovered.sender, intent.sender);
        assert_eq!(recovered.sell_token.symbol, intent.sell_token.symbol);
    }

    #[test]
    fn test_decrypt_fails_with_insufficient_shares() {
        let intent = make_test_intent();
        let ks = ThresholdKeySet::generate(3, 5);
        let encrypted = encrypt_intent(&intent, &ks.encryption_key);

        let dec_shares = make_decryption_shares(&encrypted.ciphertext, &ks.shares[..2]);

        let result = decrypt_intent(&encrypted, &dec_shares, 3);
        assert!(result.is_err());
    }
}
