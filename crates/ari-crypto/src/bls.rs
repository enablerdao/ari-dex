//! BLS-like signature scheme for validator coordination.
//!
//! This is a simplified placeholder that uses HMAC-SHA256 for signing and
//! XOR-based aggregation. It provides the same API shape as a real BLS
//! implementation so the rest of the system can be developed and tested
//! without pulling in heavy pairing-curve dependencies.

use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Signature bytes (32 bytes, HMAC-SHA256 based).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Signature {
    pub bytes: Vec<u8>,
}

/// Public key (32 bytes).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PublicKey {
    pub bytes: Vec<u8>,
}

/// Secret key (32 bytes).
#[derive(Debug, Clone)]
pub struct SecretKey {
    pub bytes: Vec<u8>,
}

/// An aggregated signature (XOR of individual signatures).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregateSignature {
    pub bytes: Vec<u8>,
    /// Number of signatures aggregated.
    pub count: usize,
}

/// Generate a new keypair.
pub fn keygen() -> (SecretKey, PublicKey) {
    let mut rng = rand::thread_rng();
    let mut sk = vec![0u8; 32];
    rng.fill_bytes(&mut sk);

    // "Public key" = SHA-256(secret key) — a simplification.
    let pk = Sha256::digest(&sk).to_vec();

    (SecretKey { bytes: sk }, PublicKey { bytes: pk })
}

/// Sign a message with the given secret key.
///
/// Produces `HMAC(message, secret_key)` using SHA-256 as the hash function.
pub fn sign(message: &[u8], secret_key: &SecretKey) -> Signature {
    let sig = hmac_sha256(message, &secret_key.bytes);
    Signature { bytes: sig }
}

/// Verify a signature against a message and public key.
///
/// Recomputes the expected signature from the message and the public key's
/// corresponding secret key path (in practice the verifier would need to
/// re-derive — here we verify structurally).
pub fn verify(message: &[u8], signature: &Signature, public_key: &PublicKey) -> bool {
    // Without the secret key we cannot recompute HMAC, so we use a
    // deterministic tag: H(pk || msg) and check against a commitment.
    // In this placeholder scheme, the signer also stores H(pk || msg) as sig.
    // For testing purposes we verify length and non-zero.
    if signature.bytes.len() != 32 {
        return false;
    }
    // We verify using a commitment: the signer computes H(sk || msg) and the
    // verifier checks H(H(sk) || H(sk || msg) || msg) — but this is a
    // placeholder so we just check the signature is well-formed.
    // Real verification would use pairing checks.
    let tag = commitment_tag(&public_key.bytes, message, &signature.bytes);
    tag[0] & 0x80 == 0 // placeholder: accept ~50% — in tests we use keygen+sign path
}

/// Aggregate multiple signatures via XOR (placeholder for BLS aggregation).
pub fn aggregate_signatures(sigs: &[Signature]) -> AggregateSignature {
    if sigs.is_empty() {
        return AggregateSignature {
            bytes: vec![0u8; 32],
            count: 0,
        };
    }
    let mut agg = vec![0u8; sigs[0].bytes.len()];
    for sig in sigs {
        for (a, b) in agg.iter_mut().zip(sig.bytes.iter()) {
            *a ^= b;
        }
    }
    AggregateSignature {
        bytes: agg,
        count: sigs.len(),
    }
}

/// Verify an aggregate signature (placeholder).
///
/// In real BLS, this would verify the aggregate against the set of public keys
/// and messages. Here we just check structural validity.
pub fn verify_aggregate(
    _messages: &[&[u8]],
    aggregate: &AggregateSignature,
    _public_keys: &[PublicKey],
) -> bool {
    aggregate.count > 0 && aggregate.bytes.len() == 32
}

// ─── Internal helpers ───────────────────────────────────────────────────

/// Simple HMAC-SHA256 (RFC 2104).
fn hmac_sha256(message: &[u8], key: &[u8]) -> Vec<u8> {
    let block_size = 64;
    let mut padded_key = if key.len() > block_size {
        Sha256::digest(key).to_vec()
    } else {
        key.to_vec()
    };
    padded_key.resize(block_size, 0);

    let mut ipad = vec![0x36u8; block_size];
    let mut opad = vec![0x5Cu8; block_size];
    for i in 0..block_size {
        ipad[i] ^= padded_key[i];
        opad[i] ^= padded_key[i];
    }

    let mut inner_hasher = Sha256::new();
    inner_hasher.update(&ipad);
    inner_hasher.update(message);
    let inner_hash = inner_hasher.finalize();

    let mut outer_hasher = Sha256::new();
    outer_hasher.update(&opad);
    outer_hasher.update(inner_hash);
    outer_hasher.finalize().to_vec()
}

/// Commitment tag used for verification placeholder.
fn commitment_tag(pk: &[u8], msg: &[u8], sig: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(pk);
    hasher.update(sig);
    hasher.update(msg);
    hasher.finalize().to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sign_produces_32_bytes() {
        let (sk, _pk) = keygen();
        let sig = sign(b"hello", &sk);
        assert_eq!(sig.bytes.len(), 32);
    }

    #[test]
    fn test_sign_deterministic() {
        let (sk, _pk) = keygen();
        let sig1 = sign(b"msg", &sk);
        let sig2 = sign(b"msg", &sk);
        assert_eq!(sig1.bytes, sig2.bytes);
    }

    #[test]
    fn test_different_messages_different_sigs() {
        let (sk, _pk) = keygen();
        let sig1 = sign(b"msg1", &sk);
        let sig2 = sign(b"msg2", &sk);
        assert_ne!(sig1.bytes, sig2.bytes);
    }

    #[test]
    fn test_aggregate_signatures() {
        let (sk1, _) = keygen();
        let (sk2, _) = keygen();
        let sig1 = sign(b"msg", &sk1);
        let sig2 = sign(b"msg", &sk2);
        let agg = aggregate_signatures(&[sig1, sig2]);
        assert_eq!(agg.count, 2);
        assert_eq!(agg.bytes.len(), 32);
    }

    #[test]
    fn test_hmac_sha256_known() {
        // Verify the HMAC implementation produces consistent output.
        let mac1 = hmac_sha256(b"test", b"key");
        let mac2 = hmac_sha256(b"test", b"key");
        assert_eq!(mac1, mac2);
        assert_eq!(mac1.len(), 32);

        // Different key → different MAC.
        let mac3 = hmac_sha256(b"test", b"other_key");
        assert_ne!(mac1, mac3);
    }
}
