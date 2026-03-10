//! Intent encryption and decryption for MEV protection.

use ari_core::Intent;

/// Encrypted intent payload.
#[derive(Debug, Clone)]
pub struct EncryptedIntent {
    /// Ciphertext bytes.
    pub ciphertext: Vec<u8>,
    /// Nonce used for encryption.
    pub nonce: [u8; 12],
}

/// Encrypts an intent so it cannot be read until decryption threshold is met.
///
/// Uses the threshold encryption public key to encrypt the serialized intent.
pub fn encrypt_intent(_intent: &Intent, _public_key: &[u8]) -> EncryptedIntent {
    // TODO: Serialize intent and encrypt with threshold public key
    EncryptedIntent {
        ciphertext: Vec::new(),
        nonce: [0u8; 12],
    }
}

/// Decrypts an encrypted intent using the combined decryption key.
pub fn decrypt_intent(
    _encrypted: &EncryptedIntent,
    _decryption_key: &[u8],
) -> ari_core::Result<Intent> {
    // TODO: Decrypt ciphertext and deserialize back to Intent
    Err(ari_core::AriError::InternalError(
        "decryption not implemented".into(),
    ))
}
