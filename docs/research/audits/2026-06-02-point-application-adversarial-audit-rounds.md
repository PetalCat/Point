# Point Application Adversarial Audit - 2026-06-02

## Round 1 - Codex

Reviewed commit: `2ea4fc8`

Working tree note: the tree was already dirty before this audit. I treated existing modified and untracked files as user work and did not revert them. Notable pre-existing changes included `point/ios/`, `point/lib/main.dart`, `point/lib/services/auth_service.dart`, `point/lib/services/notification_service.dart`, `point/pubspec.yaml`, `pubspec.lock`, and existing audit material under `docs/research/audits/`.

Scope: Flutter app, iOS scaffold, Android native geofence code, Rust MLS FFI crate, Axum server, SQLite migrations, federation code, items and bridges APIs, WebSocket protocol, marketing website claims, Docker/self-hosting configuration, and available tests.

Verdict: NO-GO for a privacy/security MVP. The codebase has promising pieces, but several core claims are either broken, not enforced at the server boundary, or contradicted by storage and platform implementation details. The dangerous theme is that the product reads like "zero-knowledge privacy-first location sharing", while the implementation still has server-side authorization gaps, plaintext place storage, non-durable MLS state, fake per-recipient precision, and incomplete iOS/background paths.

Verification run:

- `flutter test` in `point/`: passed. Only one widget smoke test was present.
- `flutter analyze` in `point/`: failed with 39 issues, including unused imports, deprecated secure-storage options, dead fields, and style warnings.
- `cargo test --workspace` at repo root: passed. `point-core` has 4 crypto tests. `point-server` has 0 tests.

External references used:

- Apple background location requires the `UIBackgroundModes` key with the `location` value: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- Apple background execution modes: https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
- Apple `NSAllowsArbitraryLoads` disables ATS restrictions broadly: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads
- Firebase Cloud Messaging for Apple platforms requires APNs setup: https://firebase.google.com/docs/cloud-messaging/ios/get-started
- Android geofencing delivery behavior and background limits: https://developer.android.com/training/location/geofencing
- Android `PendingIntent` mutability flags: https://developer.android.com/reference/android/app/PendingIntent
- MLS RFC 9420, especially KeyPackage/Welcome/Commit mechanics: https://www.ietf.org/rfc/rfc9420
- OWASP SSRF prevention guidance, including DNS/IP validation and private network checks: https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html
- OWASP MASVS storage requirements for sensitive mobile data: https://mas.owasp.org/MASVS/05-MASVS-STORAGE/

## Executive Findings

### P0-01 - iOS cannot currently satisfy the core product promise

Severity: BLOCKING

The iOS client is not a functioning privacy-equivalent client. `point/lib/main.dart:60` explicitly skips `RustLib.init()` on iOS, but `CryptoService` later depends on the Rust FFI handle for MLS. That makes native E2E sharing on iOS non-functional or crash-prone. `point/lib/main.dart:65-70` also initializes Firebase only on Android, so the current app does not register iOS FCM/APNs push handling.

The iOS plist has location usage strings but lacks `UIBackgroundModes` for `location` and `remote-notification`, and lacks `BGTaskSchedulerPermittedIdentifiers`. Apple documents that apps receiving background location updates need `UIBackgroundModes` with `location`. The same plist also sets broad `NSAllowsArbitraryLoads` in `point/ios/Runner/Info.plist:31-35`, which disables ATS restrictions globally, and contains a Google Maps API key inline at `point/ios/Runner/Info.plist:29-30`.

The auth storage fallback makes this worse. `point/lib/services/auth_service.dart:11-25` stores auth tokens in `SharedPreferences` on every non-Android platform, including iOS, because secure storage is disabled to avoid a plugin crash. For a privacy-first location app, iOS cannot be considered shippable until tokens, MLS credentials, and location cache data are stored in platform-secure storage.

Recommended fix:

1. Treat iOS as unsupported in product copy and release builds until Rust FFI, Keychain storage, APNs/FCM, background location modes, and background task behavior work in a real device build.
2. Initialize `RustLib` on iOS or gate every MLS-dependent feature behind an explicit unsupported state.
3. Use iOS Keychain for tokens and persistent MLS identity/group state. Fix the `flutter_secure_storage` integration rather than falling back to plaintext preferences.
4. Add only the necessary ATS exceptions, not global `NSAllowsArbitraryLoads`.
5. Configure APNs credentials in Firebase, entitlements, notification permissions, and background data handling.

### P0-02 - Direct user sharing and temporary sharing are not actually reliable location-sharing features

Severity: BLOCKING

Direct-share MLS setup uses deterministic group IDs beginning with `dm:` in `point/lib/services/crypto_service.dart:129-139`. After creating a direct MLS group, `_addMemberByUserId` always calls `sendMlsCommit` at `point/lib/services/crypto_service.dart:285-286`. The client always posts commits to `/api/mls/commit` at `point/lib/services/api_service.dart:559-573`.

The server tries to special-case `dm:` groups by skipping the sender membership check at `point-server/src/api/mls.rs:216-224`, but then immediately calls `db::groups::get_members(&body.group_id)` at `point-server/src/api/mls.rs:231-234`. A `dm:` direct share is not a server group, so this path returns "group not found". Direct MLS setup can therefore fail after sending or attempting to send the Welcome, leaving direct sharing partially initialized.

Temporary shares are also incomplete. The API creates temporary shares in `point-server/src/api/shares.rs:235-283`, and the DB has recipient lookup in `point-server/src/db/shares.rs:294-318`, but the WebSocket location path authorizes local direct delivery only through `db::shares::are_sharing` at `point-server/src/ws/handler.rs:294-306` and `point-server/src/ws/handler.rs:460-475`. That helper checks only permanent `user_shares` at `point-server/src/db/shares.rs:335-355`. It ignores active temporary shares. On the client side, `HomeScreen` activates direct recipients only from permanent shares at `point/lib/screens/home_screen.dart:158-168`, and `SharingNotifier.createTempShare` simply returns the API response at `point/lib/providers/sharing_provider.dart:242-249` without activating relay or establishing MLS.

Result: "share temporarily for an hour then automatically drop off" is mostly a database record and notification, not a working location delivery path unless the users already have a permanent share.

Recommended fix:

1. Model direct-share sessions separately from group membership, or create a real server-side DM group table with members.
2. Make `send_commit` route `dm:` commits to exactly the two DM members without calling `groups::get_members`.
3. Add active temporary shares to server authorization before storage and before delivery.
4. Activate client relay and MLS setup for temporary shares, then stop relay on expiry or cancellation.
5. Add integration tests for accept direct share, restart both clients, create temporary share, expire temporary share, and verify delivery stops.

### P0-03 - MLS state is ephemeral and recovery is unsafe

Severity: BLOCKING

`CryptoService.init` creates a new `PointCryptoHandle` every launch at `point/lib/services/crypto_service.dart:23-29`. The underlying Rust `PointCrypto::new` generates a new signer and in-memory group map at `point-core/src/crypto.rs:23-44`. There is no durable OpenMLS storage, no persisted signing identity, no persisted group epoch, and no persisted pairwise/group membership state.

Group setup on app start recreates MLS groups for group owners if `crypto.hasGroup` is false at `point/lib/providers/group_provider.dart:50-67`. Since `hasGroup` is only an in-memory map, a restart makes the owner create a fresh MLS group for an existing server group. Non-owners rely on pending Welcome messages, but processed messages are acknowledged at `point/lib/services/crypto_service.dart:73-104` and then marked processed server-side at `point-server/src/api/mls.rs:322-336`. Once acknowledged, they cannot be replayed after local MLS state is lost.

The decrypt path also falls back to plaintext JSON when not initialized, when no MLS group exists, or when MLS decrypt fails at `point/lib/services/crypto_service.dart:223-257`. That fallback might have been useful during migration, but it weakens the invariant that location blobs must never be accepted as plaintext.

MLS itself is a reasonable protocol choice, but RFC 9420 assumes clients maintain protocol state across epochs. This implementation does not. The result is a system that may encrypt briefly in one foreground session, then lose the ability to decrypt history or continue group state across restart.

Recommended fix:

1. Persist the MLS provider storage, signing identity, credentials, group state, epoch, and group ID map.
2. Do not acknowledge Welcome/Commit messages until they are durably applied.
3. Add a safe resync/rekey protocol for lost devices instead of silently recreating groups.
4. Remove plaintext decrypt fallback from production. If migration support is needed, version the envelope and require explicit server/client migration mode.
5. Consume key packages once used. The server has `delete_key_package` in `point-server/src/db/mls.rs:63-69`, but it is unused.

### P0-04 - Location authorization happens too late or not at all

Severity: BLOCKING

The WebSocket server stores the encrypted current location before checking whether the sender is authorized to send to the recipient. In `handle_location_update`, it writes to `location_updates` at `point-server/src/ws/handler.rs:190-207` and writes history at `point-server/src/ws/handler.rs:209-222`, then later checks local direct-share authorization at `point-server/src/ws/handler.rs:294-306`. The batch path repeats this pattern by writing history at `point-server/src/ws/handler.rs:354-369` and latest location at `point-server/src/ws/handler.rs:371-390` before checking the direct share at `point-server/src/ws/handler.rs:460-475`.

Group delivery is weaker: for `recipient_type == "group"`, the server gets the group's members and fans out at `point-server/src/ws/handler.rs:237-250` and `point-server/src/ws/handler.rs:405-419`, but does not verify the sender is actually a member of that group or that the sender has sharing enabled for that group. Any authenticated user who knows a group ID can attempt to inject encrypted blobs into that group's stream and server history.

Federated direct delivery is also sent without a local relationship check at `point-server/src/ws/handler.rs:257-292` and `point-server/src/ws/handler.rs:424-458`.

Recommended fix:

1. Move all authorization before any DB write or fan-out.
2. Define a single `can_send_location(sender, recipient_type, recipient_id)` server function covering groups, direct shares, active temporary shares, link shares, federated shares, ghost state, and group-level sharing settings.
3. Fail closed on authorization lookup errors. The ghost path currently logs and allows broadcast if the DB check fails at `point-server/src/ws/handler.rs:185-187`.
4. Add regression tests proving unauthorized blobs are neither delivered nor stored.

### P0-05 - Per-member precision controls are not implemented at the privacy boundary

Severity: BLOCKING

The product says users can choose exact, approximate, or city precision per member. The client always builds `LocationData` from exact coordinates at `point/lib/providers/location_provider.dart:422-431`, then sends that same JSON to every active group and active user at `point/lib/providers/location_provider.dart:443-489` and `point/lib/providers/location_provider.dart:491-562`. There is no recipient-specific coordinate reduction before encryption.

The server stores `precision` fields for item shares and temporary shares, and the client reads a `precision` display field from incoming messages at `point/lib/providers/location_provider.dart:957-972`, but outgoing location WebSocket messages do not include precision, and the server does not enforce precision. A UI label saying "approximate" would not change what data the recipient can decrypt.

Recommended fix:

1. Define precision as an input to the encryption step, not just a display attribute.
2. Create per-recipient payloads: exact coordinates for exact recipients, snapped/noised coordinates for approximate recipients, and city/large-cell centroids for city recipients.
3. Include precision and privacy policy in authenticated encrypted payload metadata, and only expose non-sensitive routing metadata outside the ciphertext.
4. Test that recipients configured for approximate/city cannot decrypt exact coordinates from any path: live, batch, history, nudge, reconnect, and federation.

### P0-06 - Place and zone privacy claims are contradicted by plaintext server storage

Severity: BLOCKING

The initial schema had `encrypted_definition BLOB NOT NULL` for places at `point-server/migrations/001_initial.sql:83-91`. Later migrations added plaintext `lat`, `lon`, `radius`, `geometry_type`, and `polygon_points` columns in `point-server/migrations/004_places_geometry.sql:1-4` and `point-server/migrations/007_polygon_places.sql:1-3`.

The code now explicitly stores an empty encrypted blob and stores plaintext geometry instead. `point-server/src/db/places.rs:37-40` says it stores `X''` for `encrypted_definition` because it uses lat/lon/radius directly. API responses expose plaintext place geometry at `point-server/src/api/places.rs:31-45`, and group place creation stores plaintext values at `point-server/src/api/places.rs:129-150`.

This directly contradicts "Place definitions encrypted via MLS" and "Zone privacy means your home address is never stored or transmitted." If a personal or group place is Home or Work, the server database contains the sensitive coordinates.

Recommended fix:

1. Move place geometry back into encrypted MLS payloads.
2. Store only opaque encrypted definitions plus non-sensitive IDs/version/timestamps server-side.
3. Run geofence evaluation on device, or use a clearly documented privacy-preserving design if server-side evaluation is ever introduced.
4. Migrate existing plaintext place rows by encrypting client-side and wiping plaintext columns.

### P0-07 - Federation trusts too much and has incomplete SSRF protection

Severity: BLOCKING

Federation inbound signature verification is not enough. `handle_federated_location` at `point-server/src/api/federation.rs:185-221` delivers any signed remote `location.update` to a local recipient without checking whether the local user accepted a share from that remote sender. `handle_federated_mls` at `point-server/src/api/federation.rs:300-343` relays and stores MLS Welcome/Commit messages without checking a relationship or group membership. `handle_federated_key_request` returns local users' key packages to any signed remote server at `point-server/src/api/federation.rs:345-360`. `handle_federated_nudge` relays wake nudges without checking share status at `point-server/src/api/federation.rs:363-391`.

Outbound federation is similarly permissive. Any authenticated local user can ask `/api/federation/send` to send arbitrary `message_type` and payload values to a remote domain at `point-server/src/api/federation.rs:397-460`.

SSRF protection blocks literal private hosts and a few suffixes in `point-server/src/api/federation.rs:60-77`, but it does not resolve DNS and validate all A/AAAA results against private, loopback, link-local, multicast, and metadata ranges. OWASP specifically calls out DNS pinning/rebinding style defenses requiring resolution and IP validation.

Recommended fix:

1. Add relationship authorization to every federated message type.
2. Pin remote server identity by domain and public key after discovery. Consider TOFU with key rotation rules, or explicit operator allowlists for MVP.
3. Validate the remote inbox URL from discovery, not just the domain string, and reject private IP resolutions after DNS lookup.
4. Add nonce/message-ID replay protection, not only timestamp windows.
5. Rate-limit inbound federation by domain and message type.

### P0-08 - Item location broadcasts can be spoofed by any authenticated user

Severity: BLOCKING

`handle_item_location` looks up the item at `point-server/src/ws/handler.rs:632-640`, builds a broadcast, and sends it to the item owner plus all share recipients at `point-server/src/ws/handler.rs:642-690`. It never verifies that the authenticated WebSocket user owns the item, owns the bridge, has a capability-scoped bridge token, or is otherwise authorized to report that item's location.

That means any authenticated user who knows or guesses an `item_id` can inject encrypted item blobs into another user's map stream. Even if the blob is undecryptable, this is still stream pollution and can create misleading alerts or denial of service.

Recommended fix:

1. Require item updates to come from the item owner or from a scoped bridge credential bound to the item/provider.
2. Add signed bridge update envelopes with item ID, provider ID, monotonic timestamp, and replay protection.
3. Store and expose item last location only after authorization succeeds.
4. Add tests that unauthorized users cannot broadcast, store, ring, mark lost, or share item state.

### P1-09 - Ghost mode is a coarse safety net, not the advertised policy engine

Severity: SHOULD-FIX

The server has only a coarse global ghost flag set by `PUT /api/ghost` at `point-server/src/api/ghost.rs:15-27`. The WebSocket location path drops all outgoing location if this flag is true at `point-server/src/ws/handler.rs:178-188` and `point-server/src/ws/handler.rs:342-352`.

The richer rules are client-side in `point/lib/providers/ghost_provider.dart`: schedule, battery, place, timer, per-group targeting, and exceptions. They sync only a single `state.isGhostActive` boolean to the server at `point/lib/providers/ghost_provider.dart:257-264`. If one group is ghosted, the server global flag may block all shares. If a client bug or background-task failure misses a transition, the server does not independently know which group/member should be suppressed. On iOS, `Workmanager` is Android-only in practice, and the iOS BGTask equivalent is absent.

Presence leaks also bypass ghost semantics. Presence updates broadcast online state, battery, and activity to all group peers at `point-server/src/ws/handler.rs:693-735`, without checking whether the user is ghosted for that group.

Recommended fix:

1. Decide whether ghost mode is global only for MVP or truly per-recipient/per-rule.
2. If rich ghost rules are required, persist an encrypted or privacy-minimized policy representation that the server can enforce without learning sensitive place details.
3. At minimum, enforce per-group sharing state server-side and suppress presence when ghosted.
4. Fail closed on ghost DB errors.

### P1-10 - Location history is not audience-bound

Severity: SHOULD-FIX

History points are stored only by `user_id`, `encrypted_blob`, source, and timestamp in `point-server/src/db/history.rs` and are written from all live and batch paths at `point-server/src/ws/handler.rs:209-222` and `point-server/src/ws/handler.rs:354-369`. The history API then allows any direct share or any shared group member to fetch the target user's history at `point-server/src/api/history.rs:33-57`.

The history table does not record the original recipient type, recipient ID, MLS group, epoch, precision policy, or authorization audience. A recipient can receive ciphertext and metadata for periods or audiences they were not part of. In many cases they will not be able to decrypt it, especially after MLS state loss, but the API boundary is still wrong for a privacy product.

Recommended fix:

1. Store history per audience, not just per user.
2. Include `recipient_type`, `recipient_id`, MLS group/session ID, precision policy, and retention class.
3. Authorize history reads against the exact audience and time interval.
4. Provide explicit user controls for retention, deletion, and whether history is shared at all.

### P1-11 - Android geofence "survive kill/doze" is overclaimed

Severity: SHOULD-FIX

The Android manifest declares background location and a geofence broadcast receiver. That is the right starting point. But `point/android/app/src/main/kotlin/com/petalcat/point/GeofenceBroadcastReceiver.kt` keeps pending events in an in-memory static list and emits them only when the Flutter activity/event channel attaches. There is no durable event queue, no headless Flutter callback, and no WorkManager handoff for delivery when the app process is dead.

Android documentation notes background geofence events are delivered through intents and can be delayed in the background. A broadcast receiver can wake the app process, but this implementation can still lose events between process death, receiver invocation, and UI subscription. `GeofenceManager.kt` also uses `PendingIntent.FLAG_MUTABLE`; immutable is the safer default unless mutation is required.

Recommended fix:

1. Persist geofence events immediately in the receiver, then drain them from Flutter.
2. Use WorkManager or a foreground service path when an event must trigger network work.
3. Use immutable `PendingIntent` where possible.
4. Add device/instrumentation tests for process-killed geofence delivery and reboot/re-registration behavior.

### P1-12 - Push handling is not enough for location nudges, geofence alerts, or iOS background refresh

Severity: SHOULD-FIX

The server sends FCM wake pushes for several events, but the Flutter background FCM handler only initializes Firebase at `point/lib/main.dart:49-53`; it does not inspect `message.data`, route nudges, start a location fix, sync MLS messages, or surface geofence/proximity notifications.

Foreground message handling in `HomeScreen` wakes location only for nudge types at `point/lib/screens/home_screen.dart:98-113`. Geofence local notifications are shown only when a WebSocket `place.triggered` message is received at `point/lib/screens/home_screen.dart:128-156`. If the app is offline/backgrounded and receives a data push, there is no equivalent durable handler.

Recommended fix:

1. Define push data schemas for `location.nudge`, `place.triggered`, `mls.welcome`, `mls.commit`, and share events.
2. Implement Android and iOS background handlers that do the minimum safe work and respect OS execution limits.
3. Separate privacy-safe wake pushes from user-visible notifications.
4. Add delivery tests for foreground, background, terminated, offline, and notification-denied states.

### P1-13 - Sensitive local data is cached outside secure storage

Severity: SHOULD-FIX

Location cache writes `people`, `myLat`, and `myLon` to `SharedPreferences` at `point/lib/providers/location_provider.dart:170-190`. Remote exact coordinates and the user's last known position are therefore stored in ordinary app preferences. Zone-learning data is also persisted through shared preferences in `point/lib/services/zone_learning_service.dart`.

On iOS, auth tokens also fall back to `SharedPreferences` at `point/lib/services/auth_service.dart:11-25`. OWASP MASVS-STORAGE expects sensitive mobile data to be stored securely. For this app, location cache, zones, auth tokens, device identity, MLS state, and notification tokens are sensitive.

Recommended fix:

1. Encrypt local caches at rest using platform key material.
2. Store auth tokens and MLS identity in Android Keystore/iOS Keychain backed storage.
3. Add retention controls and a "clear local cache" operation.
4. Avoid caching exact remote coordinates unless necessary for offline UX.

### P1-14 - Self-hosting defaults are unsafe

Severity: SHOULD-FIX

`point-server/docker-compose.yml:13` defaults `JWT_SECRET` to `change-me-in-production`. If an operator copies the compose file without setting the variable, every deployment shares a known JWT signing secret. For a self-hosted app aimed at non-expert households, dangerous defaults matter.

`point-server/src/main.rs` loads FCM credentials from a hardcoded `firebase-admin.json` path, and the repo has mixed secret handling: Android/Firebase files are ignored, while `point/ios/Runner/GoogleService-Info.plist` exists untracked and `Info.plist` contains a Google Maps key. This creates a clean-clone setup gap and a leakage risk.

Recommended fix:

1. Refuse to start with a default or too-short `JWT_SECRET`.
2. Generate a secure secret in documented setup flows, or require explicit operator configuration.
3. Move provider credentials to documented environment variables/secrets mounts.
4. Add a clean-clone setup check for all required mobile/server config.

### P1-15 - Protocol and infrastructure claims are ahead of implementation

Severity: SHOULD-FIX

The server depends on `prost` and `prost-build` in `point-server/Cargo.toml:19-32`, but no `.proto` files exist in the repo and the WebSocket client/server use JSON envelopes (`point/lib/services/ws_service.dart:85-124`, `point-server/src/ws/handler.rs`). Protobuf is not implemented.

PostgreSQL is also not implemented. `point-server/Cargo.toml:9` enables both `postgres` and `sqlite` features, but `point-server/src/db/mod.rs:16-24` hardcodes `SqlitePool` and migrations use SQLite syntax. A `postgres://` `DATABASE_URL` will not work.

Recommended fix:

1. Remove unused protocol/dependency claims until implemented, or implement a versioned binary protocol with compatibility tests.
2. If Postgres is in scope, add a database abstraction, separate migrations, CI for both backends, and explicit operator docs.
3. Keep SQLite as the only advertised backend until Postgres passes the same test suite.

### P1-16 - Bridges and items are shells, and anti-surveillance is incomplete

Severity: SHOULD-FIX

Bridge registry and bridged entity APIs exist, and `bridge_entities.rs` blocks sharing bridged people at `point-server/src/api/bridge_entities.rs:225-244`. That is good intent. But the actual bridges listed in the product narrative are not implemented. There is no OwnTracks MQTT ingestion, Apple Find My bridge, Google Maps bridge, bridge daemon lifecycle, heartbeat UI, or provider-specific credential model.

Items are also mostly CRUD/share scaffolding. `point/lib/providers/item_provider.dart` loads and creates items, but no full UI/backend integration exists for tracker discovery, ring, lost mode, owner-proof, or provider-specific actions. Combined with P0-08, the current item path is not safe enough to expose.

Recommended fix:

1. Keep bridges and items behind feature flags.
2. Build OwnTracks first because it has an official MQTT/HTTP model and fewer account-abuse risks than consumer-platform scraping.
3. Use capability-scoped bridge credentials rather than ordinary user WebSocket auth for device updates.
4. Document that bridged people are private-to-owner and non-shareable unless explicit consent flows exist.

### P1-17 - Website/product copy overstates the current truth

Severity: SHOULD-FIX

The website still presents future or partial features as available. Examples:

- `website/src/routes/+page.svelte:27-30` says Point bridges Find My, Google Maps, Life360, and more into a single encrypted app.
- `website/src/routes/+page.svelte:81-88` claims E2E encryption, instant geofence push notifications, temporary shares, self-hosting, and anti-surveillance in a way that reads as implemented.
- `website/src/routes/+page.svelte:109-112` says bridges encrypt at the edge and the server stays zero-knowledge.
- `website/src/routes/features/+page.svelte:35-39` claims fully E2E MLS, zero-knowledge server architecture, and bridge edge encryption.
- `website/src/routes/features/+page.svelte:67-72` advertises temporary share links, but link-based temporary shares are not built.

This is a trust problem. For a privacy product, overclaiming security features is itself a security issue because users make risk decisions based on the copy.

Recommended fix:

1. Add a claims gate: every marketing claim must link to a passing test, design doc, or "coming soon" label.
2. Split "available now", "prototype", and "planned" in the UI and docs.
3. Remove zero-knowledge claims until places, history, server authorization, MLS persistence, and bridges are fixed.

### P1-18 - Test coverage is far below the risk profile

Severity: SHOULD-FIX

The Rust core has a few crypto tests, but `point-server` reports 0 tests. The Flutter app has a single startup smoke test. The highest-risk logic has no automated coverage: WebSocket auth, group authorization, temp-share expiry, ghost fail-closed behavior, MLS restart, direct-share DM setup, federation relationship checks, item spoofing, background push, and migration behavior.

Recommended fix:

1. Add server integration tests using an in-memory SQLite database and Axum test clients.
2. Add multi-client protocol tests: Alice/Bob/Charlie, group membership, no-share rejection, temp expiry, per-recipient precision, restart recovery.
3. Add property or invariant tests for "unauthorized input never writes location/history".
4. Add mobile integration tests for secure storage, background handlers, and geofence event persistence.
5. Add CI gates for `flutter analyze`, `flutter test`, `cargo test --workspace`, server integration tests, and clean Docker builds.

### P2-19 - Authentication and rate-limit hardening needs attention

Severity: NICE-TO-FIX

Registration enforces password length, but `change_password` accepts any non-empty new password at `point-server/src/api/auth.rs`. Login rate limiting keys partly off `x-real-ip`, which is spoofable unless the app is behind a trusted reverse proxy that scrubs/sets the header. WebSocket location rate limits count one batch update as one message, but each batch can contain many fixes, so history writes can exceed the intended effective location-write rate.

Recommended fix:

1. Reuse password validation everywhere passwords are accepted.
2. Trust client IP headers only from configured reverse proxies.
3. Rate-limit by effective writes, not only WebSocket envelopes.
4. Add account lockout/backoff and audit logging suitable for household operators.

## Recommended Remediation Order

### Phase 0 - Stop the trust bleed

1. Mark iOS, bridges, item tracking, link shares, Postgres, Protobuf, and zero-knowledge place definitions as not available.
2. Remove or soften website claims that are not currently true.
3. Disable federation by default, or restrict it to an explicit allowlist while relationship checks and SSRF protections are repaired.
4. Refuse startup with default `JWT_SECRET`.

### Phase 1 - Rebuild the privacy boundary

1. Implement server authorization before storage for every location-like write: live, batch, history, federated, items, places, geofence triggers, and nudges.
2. Create reusable policy checks for group membership, active share, temporary share, link share, precision, ghost, presence, and federation.
3. Make unauthorized operations fail closed and leave no DB residue.
4. Add integration tests around these invariants before expanding features.

### Phase 2 - Make MLS production-grade

1. Persist MLS identity, credential, OpenMLS storage, group state, pairwise group state, and group epochs.
2. Ack Welcome/Commit messages only after durable apply.
3. Consume key packages server-side and associate them with clients/devices.
4. Version ciphertext envelopes and remove plaintext fallback in production.
5. Add rekey/remove-member/device-loss flows.

### Phase 3 - Finish real privacy controls

1. Implement per-recipient precision before encryption.
2. Encrypt place definitions and migrate plaintext place geometry out of the server DB.
3. Audience-bind history and retention.
4. Encrypt local mobile caches and use platform secure storage everywhere.
5. Suppress or scope presence under ghost/sharing rules.

### Phase 4 - Platform reliability

1. Finish iOS: Rust FFI, Keychain, APNs/FCM, background location modes, BGTaskScheduler where appropriate, and real-device testing.
2. Harden Android geofences with durable receiver storage and background-safe delivery.
3. Implement background push handlers for nudge, geofence, MLS, and share events.
4. Add end-to-end mobile tests that cover foreground, background, killed, denied-permission, and restart states.

### Phase 5 - Bridges and items after native sharing is trustworthy

1. Build OwnTracks first behind a feature flag.
2. Add bridge credentials that are scoped to a bridge and provider, not full user auth.
3. Implement item owner proofs, update authorization, ring/lost actions, and provider status.
4. Treat Apple Find My, Google Maps, Life360, WhatsApp, and Snap Map bridges as separate risk projects because API legality, account lockout, and protocol fragility differ sharply.

## Best Practices For This Project

- Maintain a living threat model focused on stalking/abuse, compromised self-hosted servers, malicious federation peers, lost phones, curious household admins, and malicious group members.
- Turn privacy promises into invariants with tests. Example: "the server never stores unauthorized location blobs" and "approximate recipients never receive exact coordinates."
- Keep the server dumb about coordinates, but strict about authorization. Zero-knowledge is not an excuse to store or route arbitrary opaque blobs.
- Version every protocol envelope. Do not infer plaintext-vs-MLS by trying to decode JSON after decrypt failure.
- Use device-scoped identities. A user account can have multiple devices, each with its own MLS client/key packages and revocation path.
- Prefer feature flags over half-shipped privacy features. Hidden incomplete paths are acceptable; advertised incomplete paths are not.
- For self-hosting, choose safe defaults for non-experts: mandatory strong secrets, closed registration by default, TLS/proxy guidance, backup/restore docs, and visible server health.
- Add a release checklist that includes clean clone setup, Docker build, mobile release build, analyzer/test pass, secrets scan, and claims audit.

## Bottom Line

Point has a strong product idea and the skeleton of a serious architecture, but the present implementation is not yet a trustworthy privacy-first location sharing app. The most urgent fixes are not new features. They are boundary repairs: authorization before storage, durable MLS, truthful precision controls, encrypted places, secure local storage, and honest platform support.

## Round 2 - Codex Backend-First Pass

Reviewed commit: `64e1c67`

Working tree note: this round was run against the current checkout on June 2, 2026. The tree was dirty before and during this round. Notable dirty files included `Cargo.lock`, `point-core/Cargo.toml`, `point-core/src/crypto.rs`, `point-core/src/lib.rs`, `point/rust/src/api/crypto.rs`, Flutter files, `point/ios/`, and this audit directory. The server files inspected in this round appeared clean in `git status`, but the audit should still be treated as a current-checkout audit rather than a clean release-candidate audit.

Verdict: NO-GO. The backend is closer than Round 1 on local location authorization, but it is still not ready to be the foundation for UI. Federation, MLS direct sessions, WebSocket revocation, bridge/device identity, schema constraints, place-trigger authorization, and backend test coverage remain blockers or near-blockers.

Findings count: 12 findings (6 BLOCKING, 6 SHOULD-FIX, 0 NICE-TO-HAVE)

Verification run:

- `cargo test --workspace`: passed.
- Test coverage caveat: `point-core` now has 5 tests, including state export/restore. `point-server` still has 0 tests.
- Compiler warnings remain meaningful for backend readiness: unused `DiscoverEntityRequest.bridge_id`, unused bridge/entity update functions, unused `delete_key_package`, unused device-related tables/functions, and unused history/latest-location helpers.

Closures or partial closures observed since Round 1:

- Round 1 P0-04 is partially closed for local non-federated live/batch location updates: `point-server/src/ws/handler.rs:164-175` now centralizes local send authorization, and `point-server/src/ws/handler.rs:207-246` plus `point-server/src/ws/handler.rs:362-420` authorize before writes.
- Round 1 P0-07 is partially closed for inbound federated location, key request, and nudge: `point-server/src/api/federation.rs:207-217`, `point-server/src/api/federation.rs:372-382`, and `point-server/src/api/federation.rs:402-412` now check share relationships.
- Round 1 P0-08 is partially closed: `point-server/src/ws/handler.rs:634-649` now rejects `item.location` unless the sender owns the item. This still does not provide bridge-scoped item/device credentials.
- Round 1 P0-03 is partially addressed in Rust crypto: `point-core/src/crypto.rs:72-189` adds export/restore, and `cargo test --workspace` includes a passing state restore test. However, this is not yet enough to call MLS persistence complete because server-side MLS session contracts and client mutation persistence still have gaps.

### 1. Federated WebSocket forwarding bypasses discovery, SSRF defense, and local authorization

Claim: Backend federation must not let any authenticated local user turn the server into a signed proxy to arbitrary domains.

Evidence: The REST sender uses `discover_server` at `point-server/src/api/federation.rs:468-470`, and `discover_server` at `point-server/src/api/federation.rs:81-108` at least applies the current private-domain filter. The WebSocket location and nudge forwarding paths do not use it. They directly format `https://{domain}/federation/inbox` at `point-server/src/ws/handler.rs:303-308`, `point-server/src/ws/handler.rs:462-468`, and `point-server/src/ws/handler.rs:524-531`. They also skip `can_send_location` entirely whenever `is_federated` is true at `point-server/src/ws/handler.rs:207-214` and `point-server/src/ws/handler.rs:362-368`.

Severity: BLOCKING

Suggested change: Replace all ad hoc federation POSTs with one backend federation client that always performs discovery, remote endpoint validation, DNS/private-IP validation, message-type authorization, relationship authorization, timeout policy, and signing. Do not special-case federated recipients out of local authorization. Add integration tests for `user@127.0.0.1`, `user@localhost`, `user@attacker.example`, no-share federated location, no-share federated nudge, and batch forwarding.

### 2. Direct MLS `dm:` commits still cannot route

Claim: Backend must support direct user-to-user MLS sessions before the UI can depend on 1:1 sharing or temporary shares.

Evidence: Client direct sharing creates a `dm:` pairwise group and calls `_addMemberByUserId` at `point/lib/services/crypto_service.dart:170-178`. `_addMemberByUserId` always sends a server commit at `point/lib/services/crypto_service.dart:285-286`. The server commit endpoint skips the membership check for `dm:` at `point-server/src/api/mls.rs:216-224`, but still immediately calls `db::groups::get_members(&body.group_id)` at `point-server/src/api/mls.rs:231-234`. There is no server group row for a `dm:` ID, so direct commit fanout is structurally broken.

Severity: BLOCKING

Suggested change: Add a first-class backend direct-session table, for example `direct_mls_sessions(id, user_a, user_b, created_at, epoch, status)`, and route `dm:` commits to the two session members from that table. Alternatively create real hidden server groups for 1:1 sessions. Add tests that accepting a mutual share creates a DM session, sends Welcome and Commit, survives restart, and rejects third-party commits.

### 3. Federated MLS messages remain unauthenticated by relationship

Claim: Inbound MLS Welcome/Commit must be authorized at least as tightly as location updates and key requests.

Evidence: Inbound federated location, key request, and nudge now check `can_send_to_user`, but `handle_federated_mls` still relays and stores MLS messages after only locating the recipient. See `point-server/src/api/federation.rs:318-360`. There is no relationship check, no pending-share check, no group/session check, and no limit that the sender is allowed to alter the recipient's MLS state.

Severity: BLOCKING

Suggested change: Gate `mls.welcome` and `mls.commit` on a concrete relationship/session: pending share accept, established direct session, or group membership with federated member mapping. Reject unknown `group_id`, empty payload, invalid base64, and commits for sessions where the sender is not an authorized committer. Add replay/message IDs, not only timestamp windows.

### 4. Outbound federation REST is an arbitrary signed message sender

Claim: The backend should expose typed federation operations, not a raw "send any message type" endpoint to authenticated users.

Evidence: `/api/federation/send` accepts caller-supplied `recipient`, `message_type`, and `payload` at `point-server/src/api/federation.rs:440-465`. The Flutter API uses it for share requests, key requests, Welcome, and Commit at `point/lib/services/api_service.dart:501-567`. There is no allowlist per flow, no relationship check before `mls.welcome` or `mls.commit`, and no verification that the payload shape matches the message type before the server signs it.

Severity: BLOCKING

Suggested change: Replace the raw endpoint with typed endpoints or server-internal functions: `send_share_request`, `send_share_accept`, `request_key_package`, `send_mls_welcome`, `send_mls_commit`, `send_location_nudge`. Each must validate local authorization and payload schema before signing.

### 5. WebSocket auth ignores password-change token revocation

Claim: A password change should revoke both HTTP and WebSocket access.

Evidence: HTTP requests use `AuthUser`, which checks `password_changed_at` against token `iat` at `point-server/src/api/mod.rs:64-76`. WebSocket auth calls only `auth::verify_token` at `point-server/src/ws/mod.rs:55-59` and then starts the connection. A token issued before a password change can continue to use WebSocket location, bridge, item, and nudge paths until token expiry.

Severity: BLOCKING

Suggested change: Factor token validation into one shared async function that verifies signature, expiration, user existence, federated/local status, and `password_changed_at`. Use it in both HTTP and WebSocket auth. Add a server test: login, open WS token, change password, then assert old token cannot authenticate a new WS and any existing WS is disconnected or rejected on next message.

### 6. First-user admin assignment is raceable

Claim: Backend bootstrapping must create exactly one initial admin.

Evidence: Registration computes `is_admin` with `db::users::count_users(&state.pool).await? == 0` at `point-server/src/api/auth.rs:172-175`, then creates the user later at `point-server/src/api/auth.rs:200-207`. The comment says the insert prevents a race, but that only prevents two requests for the same user ID. Two different usernames racing on an empty DB can both observe zero users and both become admin.

Severity: BLOCKING

Suggested change: Bootstrap admin creation in a transaction or with a singleton bootstrap lock row. Alternatively require an explicit setup token for the first admin. Add a concurrency test with two simultaneous registrations for different usernames on an empty database.

### 7. Place trigger events are still client-trusted

Claim: Backend notifications must not let a client spoof arrival/departure events for arbitrary places.

Evidence: `handle_place_triggered` accepts `place_id`, `place_name`, and `event` from the WebSocket envelope at `point-server/src/ws/handler.rs:760-772`, looks up the place at `point-server/src/ws/handler.rs:774-785`, then broadcasts the client-provided name/event to all group members at `point-server/src/ws/handler.rs:787-807`. It does not verify that the sender is a member of the place's group, that the sender is the person whose transition is being reported, that `event` is one of the place's configured triggers, or that `place_name` matches the stored place.

Severity: BLOCKING

Suggested change: Verify sender membership and active sharing before accepting a trigger. Use the stored place name and stored trigger configuration, not client-supplied values. Validate `event in {"enter","exit"}` and dedupe/cool down transitions per `(place_id, user_id, event)`. Add tests for non-member spoofing, bad event names, disabled trigger types, and notification dedupe.

### 8. Backend schemas accept arbitrary policy/status values

Claim: UI should receive constrained backend state, not arbitrary strings that later layers must interpret defensively.

Evidence: The migrations define many policy columns as unconstrained `TEXT`: group role, group precision, group schedule type, bridge status, item precision, temporary share precision, and zone/share request status. Examples are `point-server/migrations/001_initial.sql:37-42`, `point-server/migrations/001_initial.sql:52`, `point-server/migrations/001_initial.sql:78`, and `point-server/migrations/001_initial.sql:127`. APIs also pass arbitrary values through: group settings at `point-server/src/api/groups.rs:205-210`, role updates at `point-server/src/api/groups.rs:215-233`, item precision at `point-server/src/api/items.rs:127-129`, bridged entity precision at `point-server/src/api/bridge_entities.rs:252-255`, and bridge heartbeat status at `point-server/src/ws/handler.rs:590-606`.

Severity: SHOULD-FIX

Suggested change: Define backend enums and CHECK constraints for role, precision, schedule type, request status, bridge status, recipient type, source type, place geometry type, place event type, and message type. Validate in API structs before database writes. Add migration tests that invalid values fail.

### 9. Bridge/entity backend cannot yet support a truthful bridge status UI

Claim: Bridge registration, heartbeat, entity discovery, and status display must exist before bridge UI.

Evidence: `DiscoverEntityRequest.bridge_id` is declared but unused, which the compiler warned about and which is visible at `point-server/src/api/bridge_entities.rs:21-29` and `point-server/src/api/bridge_entities.rs:170-200`. `confirm_entity` passes the existing `entity.bridge_id` back into the update at `point-server/src/api/bridge_entities.rs:203-221`, so it does not bind an entity to a bridge if discovery ignored the bridge ID. `register_bridge` does not validate `bridge_type` against the registry at `point-server/src/db/bridges.rs:31-66`, and there is no HTTP route exposing `list_user_bridges`, despite `point-server/src/db/bridges.rs:87-111` existing.

Severity: SHOULD-FIX

Suggested change: Add bridge-scoped credentials and HTTP APIs for list/get/delete bridges. Validate bridge type against `bridge_registry`. Make discovery require a bridge owned by the caller and store `bridge_id`. Make confirm/reject transitions explicit. Add status heartbeat expiry and tests for wrong owner, unknown bridge type, missing bridge, and stale heartbeat.

### 10. Device-scoped backend identity is still missing

Claim: A privacy-first MLS location backend needs device identities, not only user identities.

Evidence: The initial migration creates a `devices` table at `point-server/migrations/001_initial.sql:13-21`, but `rg` finds no backend code using it outside the migration. Key packages are stored only by `user_id` in `point-server/src/db/mls.rs:26-61`, FCM tokens are stored only by `(user_id, token)` in `point-server/src/db/users.rs:81-92`, and WebSocket auth tracks only `claims.sub`.

Severity: SHOULD-FIX

Suggested change: Promote devices to first-class backend objects: `device_id`, display name, platform, public identity key, MLS client ID, key packages, push tokens, last seen, revoked_at. Make MLS key packages and push tokens device-scoped. Add device revocation and rekey flows before shipping multi-device or iOS/Android parity.

### 11. Retention and replay controls are not backend-owned enough

Claim: The backend should own retention limits and timestamp sanity for location-like data.

Evidence: WebSocket live updates accept `timestamp` and `ttl` directly from the client at `point-server/src/ws/handler.rs:190-192`, then store them at `point-server/src/ws/handler.rs:229-246`. Batch updates accept arbitrary timestamp arrays at `point-server/src/ws/handler.rs:339-347` and store all history points at `point-server/src/ws/handler.rs:384-399`. `location_updates` cleanup uses client-supplied `ttl` at `point-server/src/db/locations.rs:35-44`; history cleanup is hardcoded to 30 days in `point-server/src/main.rs:88-90`. There is no max TTL, timestamp skew bound, per-user retention policy, or audience-bound retention.

Severity: SHOULD-FIX

Suggested change: Enforce max/min TTL server-side, reject timestamps too far in the future or past, store server receive time separately, make history retention configurable per user/group, and bind retention to the exact audience/session. Add tests for huge TTL, future timestamp, batch size abuse, and old timestamp insertion.

### 12. Backend lacks proof tests for the contracts the UI will depend on

Claim: The UI should only be built on backend contracts proven by tests.

Evidence: `cargo test --workspace` passes, but `point-server` has 0 tests. The warnings list several unused backend functions and fields, including bridge discovery/status and key package consumption. There are no tests for auth revocation, federation SSRF, local/federated authorization, temp-share authorization, DM MLS commits, place trigger spoofing, invite race, schema enum validation, or retention limits.

Severity: SHOULD-FIX

Suggested change: Build a backend integration test harness first. Minimum tests: register/login/invite/admin race, password-change WS revocation, group membership authorization, group sharing off, temporary share authorization and expiry, DM MLS welcome/commit, key package consume-on-use, inbound federated location/key/nudge/MLS authorization, federation private-domain rejection, item update ownership, bridge discovery ownership, place trigger membership, and retention limits. Keep UI work behind these tests.

## Backend-First Build Gate

Before new UI work, the backend should expose stable, tested contracts for:

1. Auth and session lifecycle: registration, invite mode, first-admin bootstrap, password change, token revocation, device registration, device revocation.
2. Policy engine: one server-side authorization path for groups, direct shares, temporary shares, link shares, precision, ghost, presence, history, items, bridges, and federation.
3. MLS/session backend: direct-session records, group MLS epoch/session status, device-scoped key packages, consume-on-use key packages, pending message durability, and explicit rekey flows.
4. Federation client/server: typed operations only, discovery everywhere, DNS/private-IP validation, relationship checks for every message type, replay protection, rate limits, and optional allowlist config.
5. Places and notifications: encrypted or privacy-minimized place storage, validated transition events, dedupe/cooldown, push schemas, and background-safe delivery contracts.
6. Bridges/items: bridge credentials, bridge status APIs, bridge-owned entity discovery, item update authorization, item capabilities, and owner/share visibility contracts.
7. Retention: bounded TTLs, audience-bound history, per-user/group retention settings, deletion guarantees, and migration paths.
8. Test gates: `cargo test --workspace` must include server integration tests for the above. A passing core-crypto suite is not enough.
