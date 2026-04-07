//! Ed25519 keypair for federation message signing.
//!
//! Each server generates a keypair on first boot and persists it.
//! The public key is published at /.well-known/point.
//! Outgoing federation messages are signed; incoming messages are verified.

use ed25519_dalek::{Signer, SigningKey, Verifier, VerifyingKey};
use std::path::Path;

pub struct FederationKeys {
    signing_key: SigningKey,
    pub public_key_hex: String,
}

impl FederationKeys {
    /// Load or generate federation keypair.
    /// Persists to `data_dir/federation_key` so it survives restarts.
    pub fn load_or_generate(data_dir: &str) -> Self {
        let key_path = Path::new(data_dir).join("federation_key");

        let signing_key = if key_path.exists() {
            let bytes = std::fs::read(&key_path).expect("failed to read federation key");
            let key_bytes: [u8; 32] = bytes.try_into().expect("invalid federation key size");
            SigningKey::from_bytes(&key_bytes)
        } else {
            let mut rng = rand::thread_rng();
            let key = SigningKey::generate(&mut rng);
            // Ensure parent dir exists
            if let Some(parent) = key_path.parent() {
                std::fs::create_dir_all(parent).ok();
            }
            std::fs::write(&key_path, key.to_bytes()).expect("failed to write federation key");
            tracing::info!("Generated new federation Ed25519 keypair");
            key
        };

        let public_key_hex = hex::encode(signing_key.verifying_key().to_bytes());

        Self {
            signing_key,
            public_key_hex,
        }
    }

    /// Sign a message body. Returns hex-encoded signature.
    pub fn sign(&self, body: &[u8]) -> String {
        let signature = self.signing_key.sign(body);
        hex::encode(signature.to_bytes())
    }

    /// Verify a signature from a remote server's public key.
    pub fn verify(public_key_hex: &str, body: &[u8], signature_hex: &str) -> Result<(), String> {
        let pk_bytes = hex::decode(public_key_hex)
            .map_err(|e| format!("invalid public key hex: {e}"))?;
        let pk_array: [u8; 32] = pk_bytes.try_into()
            .map_err(|_| "public key must be 32 bytes".to_string())?;
        let verifying_key = VerifyingKey::from_bytes(&pk_array)
            .map_err(|e| format!("invalid public key: {e}"))?;

        let sig_bytes = hex::decode(signature_hex)
            .map_err(|e| format!("invalid signature hex: {e}"))?;
        let sig_array: [u8; 64] = sig_bytes.try_into()
            .map_err(|_| "signature must be 64 bytes".to_string())?;
        let signature = ed25519_dalek::Signature::from_bytes(&sig_array);

        verifying_key.verify(body, &signature)
            .map_err(|e| format!("signature verification failed: {e}"))
    }
}
