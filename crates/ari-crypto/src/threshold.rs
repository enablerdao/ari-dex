//! Threshold encryption scheme for MEV protection.
//!
//! Uses Shamir's Secret Sharing for key distribution and AES-256-GCM for
//! symmetric encryption. The AES key is split into shares; any `t` out of `n`
//! shares can reconstruct the key and decrypt the ciphertext.

use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use rand::RngCore;
use serde::{Deserialize, Serialize};

/// A share of the decryption key.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyShare {
    /// 1-based index of this share.
    pub index: u32,
    /// Share data (GF(256) evaluations of the polynomial, one per key byte).
    pub data: Vec<u8>,
}

/// A threshold key set: the encryption key and `n` shares.
#[derive(Debug, Clone)]
pub struct ThresholdKeySet {
    /// WARNING: This is a symmetric encryption key, NOT a public key.
    /// It must NEVER be shared publicly. In production, use asymmetric
    /// threshold encryption (e.g., BLS-based threshold decryption).
    pub encryption_key: Vec<u8>,
    /// The generated key shares.
    pub shares: Vec<KeyShare>,
    /// Minimum shares required to reconstruct.
    pub threshold: u32,
}

/// Ciphertext produced by threshold encryption.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ciphertext {
    /// AES-GCM ciphertext.
    pub data: Vec<u8>,
    /// 12-byte nonce used for AES-GCM.
    pub nonce: [u8; 12],
}

/// A partial decryption share (for this scheme it is the reconstructed portion
/// of the key; real threshold decryption would use partial El-Gamal decryptions).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecryptionShare {
    /// Index of the share holder.
    pub index: u32,
    /// The share data (same as KeyShare.data in this simplified scheme).
    pub data: Vec<u8>,
}

impl ThresholdKeySet {
    /// Generate a new threshold key set with `total_nodes` shares where
    /// `threshold` shares are needed to decrypt.
    pub fn generate(threshold: u32, total_nodes: u32) -> Self {
        assert!(
            threshold > 0 && threshold <= total_nodes,
            "threshold must be in [1, total_nodes]"
        );

        // Generate a random 32-byte AES key.
        let mut key = vec![0u8; 32];
        OsRng.fill_bytes(&mut key);

        // Split the key using Shamir's Secret Sharing in GF(256).
        let shares = shamir_split(&key, threshold, total_nodes);

        Self {
            encryption_key: key,
            shares,
            threshold,
        }
    }
}

/// Encrypt plaintext using the encryption key (AES-256-GCM).
pub fn encrypt(plaintext: &[u8], encryption_key: &[u8]) -> Ciphertext {
    let key = aes_gcm::Key::<Aes256Gcm>::from_slice(encryption_key);
    let cipher = Aes256Gcm::new(key);

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .expect("AES-GCM encryption should not fail");

    Ciphertext {
        data: ciphertext,
        nonce: nonce_bytes,
    }
}

/// Produce a decryption share from a key share (in this simplified scheme the
/// decryption share is identical to the key share).
pub fn decrypt_share(ciphertext: &Ciphertext, share: &KeyShare) -> DecryptionShare {
    // In a real threshold scheme each participant would perform a partial
    // decryption. Here we just pass the share through so that `combine_shares`
    // can do Lagrange interpolation.
    let _ = ciphertext; // ciphertext not needed for share production in SSS.
    DecryptionShare {
        index: share.index,
        data: share.data.clone(),
    }
}

/// Combine at least `threshold` decryption shares to recover the AES key,
/// then decrypt the ciphertext.
pub fn combine_shares(
    ciphertext: &Ciphertext,
    shares: &[DecryptionShare],
    threshold: u32,
) -> Option<Vec<u8>> {
    if (shares.len() as u32) < threshold {
        return None;
    }

    // Convert DecryptionShares to the format expected by shamir_combine.
    let key_shares: Vec<KeyShare> = shares
        .iter()
        .map(|ds| KeyShare {
            index: ds.index,
            data: ds.data.clone(),
        })
        .collect();

    let key = shamir_combine(&key_shares, threshold)?;
    if key.len() != 32 {
        return None;
    }

    let aes_key = aes_gcm::Key::<Aes256Gcm>::from_slice(&key);
    let cipher = Aes256Gcm::new(aes_key);
    let nonce = Nonce::from_slice(&ciphertext.nonce);

    cipher.decrypt(nonce, ciphertext.data.as_ref()).ok()
}

// ─── Shamir's Secret Sharing over GF(256) ───────────────────────────────

/// Irreducible polynomial for GF(256): x^8 + x^4 + x^3 + x + 1 (0x11B).
fn gf256_mul(mut a: u8, mut b: u8) -> u8 {
    let mut result: u8 = 0;
    while b > 0 {
        if b & 1 != 0 {
            result ^= a;
        }
        let hi = a & 0x80;
        a <<= 1;
        if hi != 0 {
            a ^= 0x1B; // reduce modulo the irreducible polynomial
        }
        b >>= 1;
    }
    result
}

/// Multiplicative inverse in GF(256) via exponentiation (a^254 = a^{-1}).
fn gf256_inv(a: u8) -> u8 {
    if a == 0 {
        return 0;
    }
    // a^254 = a^{-1} in GF(256) via square-and-multiply.
    let mut acc = 1u8;
    let mut e: u8 = 254;
    let mut base = a;
    while e > 0 {
        if e & 1 != 0 {
            acc = gf256_mul(acc, base);
        }
        base = gf256_mul(base, base);
        e >>= 1;
    }
    acc
}

/// Evaluate polynomial at point `x` in GF(256).
fn gf256_eval(coeffs: &[u8], x: u8) -> u8 {
    let mut result = 0u8;
    for &c in coeffs.iter().rev() {
        result = gf256_mul(result, x) ^ c;
    }
    result
}

/// Split a secret into `n` shares with threshold `t` using Shamir's SSS in GF(256).
fn shamir_split(secret: &[u8], t: u32, n: u32) -> Vec<KeyShare> {
    let mut rng = rand::thread_rng();
    let mut shares: Vec<KeyShare> = (0..n)
        .map(|i| KeyShare {
            index: i + 1,
            data: Vec::with_capacity(secret.len()),
        })
        .collect();

    for &byte in secret {
        // Build a random polynomial of degree t-1 with constant term = byte.
        let mut coeffs = vec![byte];
        for _ in 1..t {
            let mut r = [0u8; 1];
            rng.fill_bytes(&mut r);
            // Ensure we don't push 0 for non-constant terms (avoid degenerate poly).
            coeffs.push(if r[0] == 0 { 1 } else { r[0] });
        }

        for (i, share) in shares.iter_mut().enumerate() {
            let x = (i + 1) as u8; // x values are 1..n
            share.data.push(gf256_eval(&coeffs, x));
        }
    }

    shares
}

/// Reconstruct the secret from `t` or more shares using Lagrange interpolation in GF(256).
fn shamir_combine(shares: &[KeyShare], t: u32) -> Option<Vec<u8>> {
    if shares.len() < t as usize {
        return None;
    }
    let shares = &shares[..t as usize];
    let secret_len = shares[0].data.len();

    let mut secret = Vec::with_capacity(secret_len);

    for byte_idx in 0..secret_len {
        let mut value = 0u8;
        for (i, share_i) in shares.iter().enumerate() {
            let xi = share_i.index as u8;
            let yi = share_i.data[byte_idx];

            // Compute Lagrange basis polynomial evaluated at x=0.
            let mut basis = 1u8;
            for (j, share_j) in shares.iter().enumerate() {
                if i == j {
                    continue;
                }
                let xj = share_j.index as u8;
                // basis *= (0 - xj) / (xi - xj) = xj / (xi ^ xj) in GF(256)
                let num = xj;
                let den = xi ^ xj;
                if den == 0 {
                    return None; // duplicate shares
                }
                basis = gf256_mul(basis, gf256_mul(num, gf256_inv(den)));
            }

            value ^= gf256_mul(yi, basis);
        }
        secret.push(value);
    }

    Some(secret)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_threshold_encrypt_decrypt() {
        let ks = ThresholdKeySet::generate(3, 5);
        assert_eq!(ks.shares.len(), 5);

        let plaintext = b"hello encrypted mempool";
        let ct = encrypt(plaintext, &ks.encryption_key);

        // Create decryption shares from the first 3 key shares.
        let dec_shares: Vec<DecryptionShare> = ks.shares[..3]
            .iter()
            .map(|s| decrypt_share(&ct, s))
            .collect();

        let recovered = combine_shares(&ct, &dec_shares, 3);
        assert!(recovered.is_some());
        assert_eq!(recovered.unwrap(), plaintext);
    }

    #[test]
    fn test_insufficient_shares() {
        let ks = ThresholdKeySet::generate(3, 5);
        let plaintext = b"secret data";
        let ct = encrypt(plaintext, &ks.encryption_key);

        let dec_shares: Vec<DecryptionShare> = ks.shares[..2]
            .iter()
            .map(|s| decrypt_share(&ct, s))
            .collect();

        let recovered = combine_shares(&ct, &dec_shares, 3);
        assert!(recovered.is_none());
    }

    #[test]
    fn test_shamir_roundtrip() {
        let secret = b"test secret 1234567890abcdef";
        let shares = shamir_split(secret, 3, 5);

        // Any 3 of 5 shares should reconstruct.
        let recovered = shamir_combine(&shares[1..4].to_vec(), 3).unwrap();
        assert_eq!(recovered, secret);

        // Different subset of 3 shares.
        let subset = vec![shares[0].clone(), shares[2].clone(), shares[4].clone()];
        let recovered2 = shamir_combine(&subset, 3).unwrap();
        assert_eq!(recovered2, secret);
    }

    #[test]
    fn test_gf256_inverse() {
        // a * a^{-1} = 1 for all nonzero a.
        for a in 1..=255u8 {
            let inv = gf256_inv(a);
            assert_eq!(gf256_mul(a, inv), 1, "failed for a={a}");
        }
    }
}
