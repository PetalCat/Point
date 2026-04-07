//! Bridge API for Point MLS encryption — exposed to Dart via flutter_rust_bridge.

use point_core::crypto::PointCrypto;
use point_core::types::AddMemberResult;

/// Opaque handle to the MLS crypto engine. Lives on Dart side as a pointer.
pub struct PointCryptoHandle {
    inner: PointCrypto,
}

/// Result of adding a member to an MLS group.
pub struct BridgeAddMemberResult {
    pub welcome: Vec<u8>,
    pub commit: Vec<u8>,
}

impl PointCryptoHandle {
    /// Create a new MLS crypto instance for this identity (e.g. "alice@point.petalcat.dev").
    pub fn new(identity: String) -> anyhow::Result<PointCryptoHandle> {
        let inner = PointCrypto::new(&identity).map_err(|e| anyhow::anyhow!("{e}"))?;
        Ok(PointCryptoHandle { inner })
    }

    /// Generate a serialized KeyPackage for key exchange.
    /// Upload this to the server so others can add you to groups.
    pub fn generate_key_package(&self) -> anyhow::Result<Vec<u8>> {
        self.inner.generate_key_package().map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Create a new MLS group. Returns the group ID bytes.
    pub fn create_group(&mut self, group_id: Vec<u8>) -> anyhow::Result<Vec<u8>> {
        self.inner.create_group(&group_id).map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Add a member to a group using their serialized KeyPackage.
    /// Returns Welcome (for new member) and Commit (for existing members).
    pub fn add_member(
        &mut self,
        group_id: Vec<u8>,
        key_package_bytes: Vec<u8>,
    ) -> anyhow::Result<BridgeAddMemberResult> {
        let result: AddMemberResult = self
            .inner
            .add_member(&group_id, &key_package_bytes)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        Ok(BridgeAddMemberResult {
            welcome: result.welcome,
            commit: result.commit,
        })
    }

    /// Process a Welcome message to join a group. Returns the group ID bytes.
    pub fn process_welcome(&mut self, welcome_bytes: Vec<u8>) -> anyhow::Result<Vec<u8>> {
        self.inner
            .process_welcome(&welcome_bytes)
            .map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Encrypt plaintext for a group. Returns ciphertext bytes.
    pub fn encrypt(&mut self, group_id: Vec<u8>, plaintext: Vec<u8>) -> anyhow::Result<Vec<u8>> {
        self.inner
            .encrypt(&group_id, &plaintext)
            .map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Decrypt ciphertext from a group. Returns plaintext bytes.
    pub fn decrypt(&mut self, group_id: Vec<u8>, ciphertext: Vec<u8>) -> anyhow::Result<Vec<u8>> {
        self.inner
            .decrypt(&group_id, &ciphertext)
            .map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Process an MLS Commit message to stay in sync with group epoch changes.
    pub fn process_commit(&mut self, group_id: Vec<u8>, commit_bytes: Vec<u8>) -> anyhow::Result<()> {
        self.inner
            .process_commit(&group_id, &commit_bytes)
            .map_err(|e| anyhow::anyhow!("{e}"))
    }

    /// Check if this instance has joined a specific group.
    #[flutter_rust_bridge::frb(sync)]
    pub fn has_group(&self, group_id: Vec<u8>) -> bool {
        self.inner.has_group(&group_id)
    }

    /// Get the number of members in a group.
    pub fn group_member_count(&self, group_id: Vec<u8>) -> anyhow::Result<usize> {
        self.inner
            .group_member_count(&group_id)
            .map_err(|e| anyhow::anyhow!("{e}"))
    }
}
