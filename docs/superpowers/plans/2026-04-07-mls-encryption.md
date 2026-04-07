# MLS Encryption Implementation Plan

**Goal:** Implement end-to-end encryption for all location data using MLS (RFC 9420) via OpenMLS. After this, the server is truly zero-knowledge — it routes encrypted blobs it cannot read.

**Architecture:** Shared Rust crate (`point-core`) compiled for both the server (native) and Flutter client (via flutter_rust_bridge). OpenMLS handles group key management, forward secrecy, and post-compromise security.

## What Changes

### Before (current):
```
Client A → base64(JSON location) → Server → base64(JSON location) → Client B
Server CAN read: lat, lon, speed, battery, everything
```

### After (with MLS):
```
Client A → MLS_encrypt(JSON location) → Server → MLS_ciphertext → Client B → MLS_decrypt → JSON location
Server sees: opaque ciphertext blob, sender ID, recipient group ID, timestamp
Server CANNOT read: lat, lon, speed, battery, activity, anything
```

## Components

### 1. point-core (Rust crate)
Shared library used by both server and Flutter client.

**Responsibilities:**
- MLS group creation and management (OpenMLS)
- Encrypt location data for a group
- Decrypt received location data
- Key package generation and management
- Group member add/remove
- Key storage abstraction (SQLCipher on mobile, in-memory for server)

**Does NOT do:**
- Network communication (that's the app/server's job)
- UI (that's Flutter's job)
- Storage (provides an interface, caller implements)

### 2. Server changes
- Store MLS key packages per user/device
- Relay MLS Welcome messages and Commits
- Stop reading location payloads (they become opaque)
- New endpoints for key package upload/download

### 3. Flutter client changes
- Call point-core via flutter_rust_bridge for encrypt/decrypt
- Store MLS state in SQLCipher (encrypted local DB)
- Upload key packages on registration
- Process Welcome messages when joining groups
- Encrypt outgoing locations, decrypt incoming

## Implementation Tasks

### Task 1: Create point-core Rust crate

Create a new Cargo workspace member:
```
point-core/
├── Cargo.toml
├── src/
│   ├── lib.rs          # Public API
│   ├── crypto.rs       # MLS operations
│   ├── storage.rs      # Key/state storage trait
│   └── types.rs        # Shared types
```

Dependencies: `openmls`, `openmls_traits`, `openmls_rust_crypto`, `serde`, `serde_json`

### Task 2: MLS Group Operations

Core functions:
```rust
// Generate a key package for this device
fn generate_key_package(identity: &[u8]) -> Result<KeyPackageBundle>

// Create a new MLS group (when creating a Point group)
fn create_group(group_id: &[u8], key_package: &KeyPackageBundle) -> Result<MlsGroup>

// Add a member to a group (returns Welcome + Commit messages)
fn add_member(group: &mut MlsGroup, their_key_package: &KeyPackage) -> Result<(Welcome, Commit)>

// Remove a member
fn remove_member(group: &mut MlsGroup, member: &LeafNodeIndex) -> Result<Commit>

// Process a Welcome message (when being added to a group)
fn process_welcome(welcome: &Welcome, key_package: &KeyPackageBundle) -> Result<MlsGroup>

// Process a Commit (group state update)
fn process_commit(group: &mut MlsGroup, commit: &Commit) -> Result<()>

// Encrypt a message for the group
fn encrypt(group: &mut MlsGroup, plaintext: &[u8]) -> Result<Vec<u8>>

// Decrypt a message from the group
fn decrypt(group: &mut MlsGroup, ciphertext: &[u8]) -> Result<Vec<u8>>
```

### Task 3: Server Key Package API

New endpoints:
- `POST /api/keys/upload` — upload your key packages (multiple for multi-device)
- `GET /api/keys/{user_id}` — download someone's key packages (to add them to a group)
- `POST /api/mls/welcome` — relay a Welcome message to a user
- `POST /api/mls/commit` — relay a Commit to group members

New table:
```sql
CREATE TABLE key_packages (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    device_id TEXT NOT NULL,
    key_package BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### Task 4: Encrypt Location Updates

In the Flutter client, change the location sending flow:
```dart
// Before:
final blob = base64Encode(utf8.encode(jsonEncode(locationData.toJson())));

// After:
final plaintext = utf8.encode(jsonEncode(locationData.toJson()));
final ciphertext = await pointCore.encrypt(groupId, plaintext);
final blob = base64Encode(ciphertext);
```

And receiving:
```dart
// Before:
final decoded = jsonDecode(utf8.decode(base64Decode(blob)));

// After:
final ciphertext = base64Decode(blob);
final plaintext = await pointCore.decrypt(senderId, ciphertext);
final decoded = jsonDecode(utf8.decode(plaintext));
```

### Task 5: Flutter Rust Bridge Integration

Set up flutter_rust_bridge to expose point-core to Dart:
- Create `point/rust/` directory with the Rust code
- Configure FRB codegen
- Build for Android (arm64, arm, x86_64)
- Expose async encrypt/decrypt functions

### Task 6: Key Exchange Flow

When a user joins a group:
1. Joiner uploads their key packages to the server
2. Group admin fetches joiner's key package
3. Admin's client creates an MLS Add Commit + Welcome
4. Server relays Welcome to the joiner
5. Server relays Commit to all existing members
6. Everyone's MLS state is updated

### Task 7: Migration

Existing unencrypted data needs a migration path:
- New groups created after this change use MLS from the start
- Existing groups get a "upgrade to encrypted" flow
- During transition, support both encrypted and unencrypted messages (check a header byte)

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| OpenMLS API instability | Pin to specific version, wrap in our own API |
| Flutter Rust Bridge complexity | Follow FRB's SvelteKit-style guide, test incrementally |
| Cross-compilation for Android | Use cargo-ndk, test on CI |
| Key storage security | Use SQLCipher on mobile, keystore for the encryption key |
| Performance on old phones | MLS operations are <1ms per research, but test on real devices |
