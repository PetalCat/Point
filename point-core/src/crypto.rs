//! MLS cryptographic operations for Point.

use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use std::collections::HashMap;

use crate::errors::{PointCryptoError, Result};
use crate::types::*;

// X25519 + ChaCha20Poly1305 + Ed25519 — strong classical security
// PQC upgrade path: MLS_256_XWING_CHACHA20POLY1305_SHA256_Ed25519 (XWing = X25519 + ML-KEM)
// Blocked on openmls_libcrux_crypto aligning with openmls 0.6 trait versions
const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519;

pub struct PointCrypto {
    provider: OpenMlsRustCrypto,
    credential: CredentialWithKey,
    signer: SignatureKeyPair,
    groups: HashMap<Vec<u8>, MlsGroup>,
}

impl PointCrypto {
    pub fn new(identity: &str) -> Result<Self> {
        let provider = OpenMlsRustCrypto::default();

        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .map_err(|e| PointCryptoError::Mls(format!("{e:?}")))?;
        signer.store(provider.storage())
            .map_err(|e| PointCryptoError::Mls(format!("{e:?}")))?;

        let credential = BasicCredential::new(identity.as_bytes().to_vec());
        let credential_with_key = CredentialWithKey {
            credential: credential.into(),
            signature_key: signer.to_public_vec().into(),
        };

        Ok(Self {
            provider,
            credential: credential_with_key,
            signer,
            groups: HashMap::new(),
        })
    }

    pub fn generate_key_package(&self) -> Result<Vec<u8>> {
        let kp_bundle = KeyPackage::builder()
            .build(
                CIPHERSUITE,
                &self.provider,
                &self.signer,
                self.credential.clone(),
            )
            .map_err(|e| PointCryptoError::KeyPackage(format!("{e:?}")))?;

        let kp: KeyPackage = kp_bundle.key_package().clone();
        let serialized = kp.tls_serialize_detached()
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;
        Ok(serialized)
    }

    pub fn create_group(&mut self, group_id: &[u8]) -> Result<Vec<u8>> {
        let config = MlsGroupCreateConfig::builder()
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build();

        let group = MlsGroup::new_with_group_id(
            &self.provider,
            &self.signer,
            &config,
            GroupId::from_slice(group_id),
            self.credential.clone(),
        )
        .map_err(|e| PointCryptoError::Mls(format!("Create group: {e:?}")))?;

        let gid = group.group_id().as_slice().to_vec();
        self.groups.insert(gid.clone(), group);
        Ok(gid)
    }

    pub fn add_member(&mut self, group_id: &[u8], key_package_bytes: &[u8]) -> Result<AddMemberResult> {
        let group = self.groups.get_mut(group_id)
            .ok_or_else(|| PointCryptoError::GroupNotFound(hex::encode(group_id)))?;

        // Deserialize as KeyPackageIn, then validate into KeyPackage
        let kp_in = KeyPackageIn::tls_deserialize_exact(key_package_bytes)
            .map_err(|e| PointCryptoError::KeyPackage(format!("{e:?}")))?;
        let kp: KeyPackage = kp_in.validate(self.provider.crypto(), ProtocolVersion::Mls10)
            .map_err(|e| PointCryptoError::KeyPackage(format!("Validate: {e:?}")))?;

        let (commit_msg, welcome_msg, _group_info) = group
            .add_members(&self.provider, &self.signer, &[kp])
            .map_err(|e| PointCryptoError::Mls(format!("Add member: {e:?}")))?;

        group.merge_pending_commit(&self.provider)
            .map_err(|e| PointCryptoError::Mls(format!("Merge: {e:?}")))?;

        let commit_bytes = commit_msg.tls_serialize_detached()
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;

        let welcome_bytes = welcome_msg.tls_serialize_detached()
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;

        Ok(AddMemberResult { welcome: welcome_bytes, commit: commit_bytes })
    }

    pub fn process_welcome(&mut self, welcome_bytes: &[u8]) -> Result<Vec<u8>> {
        let welcome_msg = MlsMessageIn::tls_deserialize_exact(welcome_bytes)
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;

        let welcome = match welcome_msg.extract() {
            MlsMessageBodyIn::Welcome(w) => w,
            _ => return Err(PointCryptoError::Mls("Not a Welcome message".into())),
        };

        let join_config = MlsGroupJoinConfig::builder()
            .use_ratchet_tree_extension(true)
            .build();

        let group = StagedWelcome::new_from_welcome(&self.provider, &join_config, welcome, None)
            .map_err(|e| PointCryptoError::Mls(format!("Stage welcome: {e:?}")))?
            .into_group(&self.provider)
            .map_err(|e| PointCryptoError::Mls(format!("Into group: {e:?}")))?;

        let gid = group.group_id().as_slice().to_vec();
        self.groups.insert(gid.clone(), group);
        Ok(gid)
    }

    pub fn encrypt(&mut self, group_id: &[u8], plaintext: &[u8]) -> Result<Vec<u8>> {
        let group = self.groups.get_mut(group_id)
            .ok_or_else(|| PointCryptoError::GroupNotFound(hex::encode(group_id)))?;

        let msg = group.create_message(&self.provider, &self.signer, plaintext)
            .map_err(|e| PointCryptoError::Mls(format!("Encrypt: {e:?}")))?;

        msg.tls_serialize_detached()
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))
    }

    pub fn decrypt(&mut self, group_id: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>> {
        let group = self.groups.get_mut(group_id)
            .ok_or_else(|| PointCryptoError::GroupNotFound(hex::encode(group_id)))?;

        let msg_in = MlsMessageIn::tls_deserialize_exact(ciphertext)
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;

        let protocol_msg = msg_in.try_into_protocol_message()
            .map_err(|_| PointCryptoError::DecryptionFailed)?;

        let processed = group.process_message(&self.provider, protocol_msg)
            .map_err(|e| PointCryptoError::Mls(format!("Decrypt: {e:?}")))?;

        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(app) => Ok(app.into_bytes()),
            ProcessedMessageContent::StagedCommitMessage(commit) => {
                group.merge_staged_commit(&self.provider, *commit)
                    .map_err(|e| PointCryptoError::Mls(format!("Merge: {e:?}")))?;
                Err(PointCryptoError::InvalidState("Commit, not app message".into()))
            }
            _ => Err(PointCryptoError::DecryptionFailed),
        }
    }

    /// Process an MLS Commit message (e.g. when a new member is added to the group).
    /// Existing members must process commits to stay in sync with the group epoch.
    pub fn process_commit(&mut self, group_id: &[u8], commit_bytes: &[u8]) -> Result<()> {
        let group = self.groups.get_mut(group_id)
            .ok_or_else(|| PointCryptoError::GroupNotFound(hex::encode(group_id)))?;

        let msg_in = MlsMessageIn::tls_deserialize_exact(commit_bytes)
            .map_err(|e| PointCryptoError::Serialization(format!("{e:?}")))?;

        let protocol_msg = msg_in.try_into_protocol_message()
            .map_err(|_| PointCryptoError::Mls("Not a protocol message".into()))?;

        let processed = group.process_message(&self.provider, protocol_msg)
            .map_err(|e| PointCryptoError::Mls(format!("Process commit: {e:?}")))?;

        match processed.into_content() {
            ProcessedMessageContent::StagedCommitMessage(commit) => {
                group.merge_staged_commit(&self.provider, *commit)
                    .map_err(|e| PointCryptoError::Mls(format!("Merge commit: {e:?}")))?;
                Ok(())
            }
            _ => Err(PointCryptoError::InvalidState("Expected commit message".into())),
        }
    }

    pub fn has_group(&self, group_id: &[u8]) -> bool {
        self.groups.contains_key(group_id)
    }

    pub fn group_member_count(&self, group_id: &[u8]) -> Result<usize> {
        let group = self.groups.get(group_id)
            .ok_or_else(|| PointCryptoError::GroupNotFound(hex::encode(group_id)))?;
        Ok(group.members().count())
    }
}
