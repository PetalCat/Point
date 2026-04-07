# Point — Design Specification

**Date:** 2026-04-04
**Status:** Draft
**Vision:** "Beeper for location" — one privacy-respecting app that aggregates all location sharing, place search, item tracking, and location-aware services into a single unified experience.

---

## 1. Problem

Location is fragmented across too many apps: Find My for Apple devices, Google Maps for Android friends, Life360 for family, Snap Map for friends, WhatsApp for temporary sharing, Tile/AirTag for items, Google/Apple Maps for places, Uber/Lyft for rides, OpenTable for reservations. Each one has a partial view. No single app shows you everything location-related in your life.

## 2. Solution

Point: a self-hostable, privacy-first, unified location app. It aggregates people, places, items, and services into one interface with a bridge architecture (like Beeper for chat).

**Core principles:**
- E2E encrypted native location sharing (server can't read it)
- Bridges for third-party services (clearly labeled trust levels)
- Self-hostable, single-binary Rust server
- Flutter client (iOS, Android, Web)
- Federation-ready addressing from day one

## 3. Architecture

### 3.1 System Overview

```
Flutter Clients (iOS / Android / Web)
    │
    │  WebSocket (Protobuf, encrypted payloads)
    │
    ▼
Point Server (Rust, Axum + Tokio)
    │
    ├── WebSocket hub (location routing, presence)
    ├── Auth / identity (user@server format)
    ├── Encrypted blob storage (zero-knowledge for native)
    ├── MQTT ingress (OwnTracks bridge)
    └── REST API (account management, invites, config)
    │
    ▼
PostgreSQL
    │
    ├── User / device identity keys
    ├── Encrypted location blobs
    ├── Group / group membership
    ├── Geofence definitions (encrypted)
    ├── Bridge configurations
    └── Item tracker metadata

External:
    Bridge Plugins (separate processes/containers)
    ├── Apple Find My bridge
    ├── Google Maps Location Sharing bridge
    ├── Life360 bridge
    ├── WhatsApp bridge (future)
    ├── Snap Map bridge (future, research phase)
    └── OwnTracks bridge (built-in MQTT ingress)
```

### 3.2 Rust Server

- **Framework:** Axum on Tokio (async, ~200K concurrent WebSocket connections per instance)
- **Deployment:** Single statically-linked binary (musl target). Optional embedded SQLite for small installs, PostgreSQL for production.
- **API surface:** WebSocket for real-time, REST for management, MQTT listener for OwnTracks
- **TLS:** Designed to sit behind Caddy/Traefik for auto-TLS. No built-in ACME.

### 3.3 Flutter Client

- **Framework:** Flutter (iOS, Android, Web from single codebase)
- **Rust integration:** Shared Rust crate via `flutter_rust_bridge` for crypto (MLS), protocol serialization (Protobuf), and core logic
- **Background location:** Custom implementation using `geolocator` + platform foreground services + significant-change monitoring (Life360 pattern)
- **Map:** Platform maps (Google Maps on Android, Apple Maps on iOS) or MapLibre for self-hosted tile servers

### 3.4 Shared Rust Crate

A single Cargo workspace crate (`point-core`) used by both server and Flutter client:
- MLS group encryption (OpenMLS)
- Protobuf message serialization/deserialization
- Protocol types and validation
- Crypto utilities (key generation, encryption/decryption)

## 4. Protocol

### 4.1 Encoding

Protobuf over WebSocket. Compact binary payloads (~45% smaller than JSON). Schema-defined messages for type safety.

### 4.2 Message Types

**Client → Server:**
| Message | Purpose |
|---------|---------|
| `location.update` | Encrypted location blob + metadata (recipients, TTL, source) |
| `location.subscribe` | Subscribe to a group or user's updates |
| `group.create` | Create a sharing group |
| `group.invite` | Invite user to group with permission level |
| `group.join` / `group.leave` | Join or leave a group |
| `place.create` / `place.update` / `place.delete` | Manage geofence places |
| `presence.update` | Online/offline/battery/activity status |
| `bridge.register` | Bridge instance announces itself |
| `bridge.heartbeat` | Bridge health check |
| `item.update` | Item tracker location update |

**Server → Client:**
| Message | Purpose |
|---------|---------|
| `location.broadcast` | Encrypted location blob from a contact (includes `source_type`) |
| `place.triggered` | Geofence event (enter/exit/dwell) |
| `presence.broadcast` | Contact presence change |
| `group.updated` | Group membership/settings changed |
| `bridge.status` | Bridge connected/disconnected/error |
| `item.broadcast` | Item tracker location update |

### 4.3 Location Blob

```
Native (E2E Encrypted):
  Server sees:
    sender: "parker@point.local"
    recipients: ["group:family"]
    encrypted_blob: <MLS ciphertext>
    timestamp: 1712345678
    ttl: 300

  Recipients decrypt to:
    lat, lon, accuracy, altitude, speed, heading,
    battery, activity, timestamp

Bridged (Re-encrypted):
  Bridge fetches plaintext from source service,
  encrypts for recipients via MLS, sends to server.
  source_type: "bridge:findmy" | "bridge:google" | etc.
  UI clearly labels bridged vs native locations.
```

### 4.4 Connection Management

- **Adaptive update frequency:** 5s when driving (>50km/h), 10s walking, 30-60s stationary. Distance threshold filter (10-20m) to suppress GPS noise.
- **Reconnection:** Exponential backoff (1s, 2s, 4s, ... up to 5 min). On reconnect: fetch current state via REST, then resume WebSocket stream.
- **Presence:** Connection-count based. User is online when >= 1 connection open. WebSocket ping/pong every 30s. Mark offline after missed pong + 10s timeout.

### 4.5 Federation-Ready Addressing

All IDs use `name@server` format from day one:
- Users: `parker@point.local`
- Groups: `family@point.local`
- Items: `keys@point.local`

Federation is not implemented in v1, but the addressing scheme means it's a routing change, not a data migration.

## 5. Encryption

### 5.1 Protocol: MLS (RFC 9420) via OpenMLS

- **Why MLS:** O(log N) re-key on membership changes, forward + backward secrecy, IETF standard, production-proven (Wire, Matrix)
- **Implementation:** OpenMLS Rust crate, accessed from Flutter via `flutter_rust_bridge`
- **Fallback:** Signal Protocol Sender Keys via libsignal if MLS tooling proves insufficient
- **Key storage:** Encrypted SQLCipher on mobile (encryption key in OS keystore), IndexedDB on web
- **Per-message overhead:** Sub-millisecond (AES-GCM + epoch advance)

### 5.2 Two Trust Places

| Place | Server sees | Crypto | UI indicator |
|------|------------|--------|-------------|
| **Native** | Encrypted blobs only | Full MLS E2E | Green "E2E" badge |
| **Bridged** | Nothing (bridge encrypts before sending) | Bridge decrypts from source, re-encrypts via MLS | Amber "Find My" / "Google" / etc. badge |

The bridge briefly sees plaintext (it must, to fetch from the source). The server never sees plaintext for either place. The UI makes the trust distinction visible.

## 6. Bridges

### 6.1 Architecture

Bridges are separate processes that connect TO the Point server (not the reverse). Each bridge:
1. Authenticates to Point with a user-scoped token
2. Authenticates to the source service with the user's credentials
3. Polls or listens for location updates from the source
4. Encrypts updates via MLS for the user's groups
5. Pushes encrypted updates to Point server

Bridges can run:
- **Server-side:** Docker container alongside the server (always-on polling)
- **On-device:** In the app or companion app (for services needing device credentials like Apple ID)
- User chooses per-bridge

### 6.2 Double Puppeting

Bridges are bidirectional. When you share your location natively in Point, the bridge can **push your location back to the source service** — so friends who only use Find My, Google Maps, or Life360 still see you without you needing to run those apps.

**How it works:**
1. User enables "double puppet" for a bridge (opt-in per bridge)
2. When Point sends a native location update, the server notifies the user's connected bridges
3. Each double-puppeted bridge receives the decrypted location (bridge must be trusted — same trust model as inbound bridging)
4. Bridge pushes the location to the source service using the user's credentials

**Per-service feasibility:**
| Service | Double Puppet | Notes |
|---------|--------------|-------|
| Apple Find My | No | Find My doesn't accept location pushes — it reads from the device directly |
| Google Maps Sharing | Possible | Could update shared location via the same cookie-based session |
| Life360 | Possible | REST API supports location check-ins |
| OwnTracks | Yes | Publish to the user's MQTT topic |
| WhatsApp | No | Live location is tied to a chat session on the device |

**Privacy note:** Double puppeting requires the bridge to see your plaintext location (same as inbound bridging). The UI clearly indicates which bridges have double puppet enabled, and it's always opt-in.

### 6.3 Bridge Status

| Service | Feasibility | Method | Fragility | MVP Priority |
|---------|------------|--------|-----------|-------------|
| **OwnTracks** | High | MQTT ingestion (official protocol) | Stable | Yes — built into server |
| **Apple Find My** | Medium | FindMy.py (reverse-engineered iCloud) | Medium (Apple can break) | Yes — high demand |
| **Google Maps Sharing** | Medium | locationsharinglib (cookie-based) | Medium-High | Yes |
| **Life360** | Low-Medium | REST API (reverse-engineered, actively blocked) | High | Later — hostile to third parties |
| **WhatsApp** | Low | Yowsup (protocol reverse-engineered) | Very High (bans unofficial clients) | Later |
| **Snap Map** | Very Low | gRPC "MUSHROOM" + Frida bypass | Extremely High | Research project, not MVP |

### 6.4 Bridge Protocol

Bridges register via the WebSocket protocol:
```
bridge.register {
  bridge_type: "findmy",
  user: "parker@point.local",
  token: "<bridge auth token>"
}

bridge.heartbeat {
  bridge_type: "findmy",
  status: "healthy" | "degraded" | "error",
  last_fetch: <timestamp>,
  error_message: <optional>
}
```

Server tracks bridge status and surfaces it to the user. If a bridge stops heartbeating, the UI shows "Find My bridge offline."

## 7. Item Trackers

### 7.1 How Trackers Work

Trackers (AirTags, Tiles, SmartTags, etc.) are fundamentally different from people:
- A tracker has no Point account — it's an **object owned by a user**
- Its location comes from a bridge, never natively from Point
- The owner registers it in Point and assigns it to a bridge

**Flow:**
1. User runs a Find My bridge (or Tile bridge, etc.)
2. Bridge authenticates to the source network with the user's credentials
3. Bridge discovers the user's trackers on that network (e.g., "Parker's AirTag - Keys", "Parker's AirTag - Backpack")
4. User confirms which trackers to import into Point and names them
5. Bridge periodically fetches tracker locations from the source network
6. Bridge encrypts each tracker's location via MLS and pushes to Point server
7. Point routes the encrypted location to the tracker's shared recipients

### 7.2 Cross-Network Tracker Sharing

This is a core differentiator. Today, you can only share an AirTag with other Apple users, a Tile with other Tile users, etc. Point breaks that wall:

**Example:** Parker has an AirTag on his keys. Dad has an Android phone with no Apple account. Today, Dad can't see the AirTag. With Point:
1. Parker's Find My bridge fetches the AirTag location
2. Parker shares the "Keys" item with his Family group
3. Bridge encrypts the location for all Family group members via MLS
4. Dad's Point app decrypts and shows the AirTag on his map

**The tracker's source network doesn't matter.** Any Point user in the group can see any shared tracker, regardless of what ecosystem they're on.

### 7.3 Tracker Sharing Model

Items use the same group/permission system as people:

- **Owner** — the user whose bridge provides the tracker data. Can share/unshare, rename, delete.
- **Shared to group** — item appears on the map and in the drawer for all group members
- **Shared to individual** — item visible only to specific users
- **Temporary share** — time-limited item sharing (e.g., "share my car's location for 2 hours")
- **Precision control** — owner can share exact location or approximate (city-level) per group

### 7.4 Tracker Actions

Depending on the source bridge's capabilities, users can trigger actions:

| Action | Description | Requires |
|--------|-------------|----------|
| **Ring / Play Sound** | Trigger the tracker's sound | Bridge relays command to source network |
| **Directions** | Navigate to last known location | Client-side (open maps) |
| **Mark as Lost** | Flag item, notify if location changes | Bridge + Point notification |
| **Last Seen** | Show when/where tracker last reported | Stored in encrypted blob |

Not all actions are available for all tracker types. The bridge reports its capabilities when registering a tracker.

### 7.5 Tracker Bridge Capabilities

| Source | Discovery | Location | Ring/Sound | Lost Mode |
|--------|----------|----------|-----------|-----------|
| **Find My (AirTag)** | Yes (via FindMy.py) | Yes | No (requires Apple device proximity) | No |
| **Tile** | Yes (via Tile API) | Yes | Yes (API supports ring) | Yes |
| **SmartTag** | Limited (SmartThings API) | Partial | Unknown | Unknown |
| **Google Find My Device** | Limited | Partial | Unknown | Unknown |
| **OwnTracks** | N/A (device is the tracker) | Yes | N/A | N/A |

### 7.6 Protocol Messages for Items

```
Client → Server:
  item.register    { name, tracker_type, bridge_id, share_to: [group|user] }
  item.update      { item_id, name?, share_to?, precision? }
  item.delete      { item_id }
  item.action      { item_id, action: "ring" | "lost" | ... }

Bridge → Server:
  item.location    { item_id, encrypted_blob, timestamp, ttl }
  item.discovered  { tracker_type, source_id, suggested_name }
  item.capabilities { item_id, actions: ["ring", "lost", ...] }

Server → Client:
  item.broadcast   { item_id, encrypted_blob, timestamp, source_type }
  item.alert       { item_id, event: "moved" | "found" | "low_battery" }
  item.discovered  { tracker_type, source_id, suggested_name }  (for user confirmation)
```

## 8. Data Model

### 7.1 Core Entities

```
User
  id: "parker@point.local"
  display_name: string
  identity_keys: MLS KeyPackages (per device)
  devices: Device[]
  avatar: optional binary

Device
  id: uuid
  user_id: user ref
  name: "iPhone 16"
  mls_key_package: bytes
  last_seen: timestamp
  push_token: optional string

Group
  id: uuid
  name: "Family"
  owner: user ref
  members: GroupMember[]
  settings: { allow_places: bool, default_precision: enum }

GroupMember
  user_id: user ref
  role: admin | member | viewer
  precision: exact | approximate | city
  schedule: always | custom { days, start_time, end_time }

Place (Geofence)
  id: uuid
  group_id: group ref
  name: "Home"
  geometry: { center: latlon, radius: meters } | { vertices: latlon[] }
  triggers: enter | exit | dwell(duration_seconds)
  notify: user_id[]
  encrypted_definition: bytes  (shared via MLS group)

Bridge
  id: uuid
  user_id: user ref
  bridge_type: "findmy" | "google" | "life360" | "owntracks" | ...
  status: connected | disconnected | error
  last_heartbeat: timestamp
  error_message: optional string

Item
  id: uuid
  owner_id: user ref
  name: "Keys"
  tracker_type: "airtag" | "tile" | "smarttag" | "google" | "owntracks"
  source_id: string (ID on the source network, e.g. AirTag serial)
  bridge_id: bridge ref (which bridge provides updates)
  shared_to: [group ref | user ref]  (who can see this item)
  precision: exact | approximate | city  (per share target)
  capabilities: ["ring", "lost", ...]  (reported by bridge)
  last_location: encrypted bytes
  last_seen: timestamp

TemporaryShare
  id: uuid
  from: user ref
  to: user ref | link_token (for shareable links)
  precision: exact | approximate
  expires_at: timestamp
  created_at: timestamp
```

### 7.2 Location Storage

The server stores only encrypted location blobs with metadata:
```
LocationUpdate
  id: uuid
  sender: user ref
  recipients: group ref | user ref
  encrypted_blob: bytes
  source_type: "native" | "bridge:findmy" | "bridge:google" | ...
  timestamp: unix epoch
  ttl: seconds (default 300, auto-deleted after expiry)
```

No location history is stored server-side. TTL ensures blobs are garbage-collected. Client-side "Map Memory" is local-only and encrypted on-device.

## 8. Features

### 8.1 MVP (v1)

**People:**
- Native location sharing (E2E encrypted via MLS)
- Groups with role-based permissions (admin/member/viewer)
- Per-member precision control (exact/approximate/city)
- Per-member schedule control (always/custom)
- Temporary sharing (time-limited, link-based)
- Presence (online/offline/battery)

**Bridges:**
- OwnTracks MQTT ingestion (built into server)
- Apple Find My bridge (also provides AirTag item tracking)
- Google Maps Location Sharing bridge
- Bridge status visibility in UI
- Item tracking via the same bridge infrastructure (Find My bridge reports both people and AirTag locations; OwnTracks reports device locations)

**Map:**
- All/People/Items filter
- Group sub-filter (Family/Friends/Work/etc.)
- Avatars on map with online indicators
- Stale/approximate contacts faded
- Bridge source badges (E2E / Find My / Google / etc.)
- Bottom drawer with person/item list
- Full-screen map toggle, draggable split

**Geofencing:**
- Circular geofence places (client-side evaluation)
- Enter/exit/dwell notifications
- Virtual geofencing for overflow beyond OS limits
- Place definitions shared via MLS (server never sees place locations)
- Place creation: group admins and members can create places; viewers cannot

**Infrastructure:**
- Self-hostable Rust server (single binary)
- PostgreSQL or embedded SQLite
- Docker Compose deployment
- First-user-is-admin onboarding
- Invite links for new users

### 8.2 Post-MVP

**People:**
- Life360 bridge
- WhatsApp bridge
- Snap Map bridge (research)

**Places:**
- Unified place search (Google Places + Yelp)
- "Go There" route comparator (drive/walk/transit/Uber/Lyft)
- Crowd/busyness data
- Parking difficulty
- Reservations (OpenTable deep links)

**Items:**
- AirTag tracking (via Find My bridge)
- Tile tracking (via Tile API/SDK)
- SmartTag tracking (Samsung, if API becomes available)

**Location Inbox:**
- Geofence alerts
- Proximity alerts
- Ride ETAs
- Delivery tracking
- Reservation reminders

**Map Memory:**
- Auto-logged timeline (on-device, encrypted)
- Place tagging and notes
- Visit history

**Infrastructure:**
- Federation protocol (server-to-server)
- Polygon geofences
- Offline maps (MapLibre + OSM tiles)
- AI features (voice search, place recommendations)

## 9. UI

### 9.1 Design Direction: "Duo"

Clean, bold split-screen layout. Map on top, list below. High contrast black-on-white. Thick typography. Confident and grown-up.

- **Top filter:** All / People / Items segmented control on the map
- **Group sub-filter:** Appears when "People" is selected (All/Family/Friends/Work)
- **Map:** Clean, minimal. Small avatars with online dots. Item pins with white background. Geofence dashed outlines.
- **Drawer:** White, rounded top corners. Person/item rows with name, bridge badge, distance, time ago.
- **Tab bar:** Map, Explore, Inbox, Profile. Modern thin-stroke icons with active indicator line.
- **Full-screen toggle:** Map expand button + draggable divider
- **Dark mode:** Planned (warm dark tones, not cold blue/gray)

### 9.2 Bridge Visibility

Every location in the UI shows its source:
- `E2E` (green) — native, server never saw it
- `Find My` (red(like an apple)) — bridged from Apple
- `Google` (amber) — bridged from Google Maps
- `Snap` (yellow) — bridged from Snap Map
- `Life360` (purple) — bridged from Life 360
- `city`? (gray) — approximate precision only

## 10. Deployment

### 10.1 Self-Hosted (Primary)

```yaml
# docker-compose.yml
services:
  db:
    image: postgres:16
    volumes: [pgdata:/var/lib/postgresql/data]

  mqtt:
    image: eclipse-mosquitto
    volumes: [mqtt_data:/mosquitto/data]

  point:
    image: point/server:latest
    depends_on: [db, mqtt]
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/point
      MQTT_URL: tcp://mqtt:1883
      LISTEN: 0.0.0.0:8080

  caddy:
    image: caddy
    ports: ["80:80", "443:443"]
    depends_on: [point]
```

### 10.2 Minimal (SQLite)

Single binary, no Docker needed:
```bash
point-server --db sqlite://point.db --listen 0.0.0.0:8080
```

### 10.3 Onboarding Flow

1. Admin deploys server
2. Admin opens web UI, creates first account (auto-admin)
3. Admin creates invite links
4. Friends open invite link, install app, create account
5. Friends join groups, optionally set up bridges

## 11. Safety & Anti-Abuse Principles

### Consent Model for Places (Geofences)

Point takes an explicit position against enabling surveillance. The geofencing system is designed to prevent misuse in domestic abuse and stalking scenarios.

**Group places:** Allowed for all users (native + bridged). Group members consented to share with that group on their respective platforms. Group places are visible to all members. Enter/exit alerts go to the group.

**Personal places:** Native Point users only, with MUTUAL CONSENT.
- Personal places only trigger for people who have explicitly opted in: "Allow [name]'s places to evaluate my location"
- Default is OFF — the zone owner must request and the other person must accept
- The other person can revoke at any time
- The other person can see "You're inside [name]'s zone" when they are

**Bridge users:** Map display only, NO place triggers.
- Bridge users (Find My, Google, Life360, etc.) did not sign up for Point
- They cannot consent to geofence evaluation because they don't know Point exists
- Their locations are shown on the map but cannot trigger any personal or group place alerts
- This is a deliberate safety decision, not a technical limitation

**Rationale:** The difference between "cool, my friend is nearby" and surveillance is consent. A person whose location is being evaluated against geofences they don't know about has no agency. Point will not be a tool for controlling or monitoring people without their knowledge.

### Server Privacy

- All native location data is E2E encrypted via MLS — server stores only ciphertext
- Bridge credentials (Apple ID, Google cookies) are stored only by the bridge process, never on the Point server
- Geofence definitions are encrypted and shared through MLS groups
- Map Memory (timeline) is encrypted on-device, never uploaded
- TTL on location blobs prevents server-side history accumulation
- Temporary share links expire and are revocable
- All WebSocket traffic over TLS (enforced by reverse proxy)
- MLS provides forward + backward secrecy with O(log N) re-keying
- Push notifications contain NO content — they are wake-up signals only. The actual notification content is decrypted on-device
- The server admin has NO access to location data, group content, or user communications

## 12. Technical Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Server language | Rust | Performance, single binary, shared crate with client |
| Server framework | Axum + Tokio | Async, ~200K WS connections, mature ecosystem |
| Client framework | Flutter | iOS + Android + Web from one codebase |
| Encryption | MLS (OpenMLS) | IETF standard, production-proven, O(log N) re-key |
| Encoding | Protobuf | Smallest payloads, schema-defined, cross-language |
| Database | PostgreSQL (prod) / SQLite (minimal) | Flexibility for self-hosters |
| Bridge architecture | Separate processes, connect TO server | Independently deployable, user-controlled |
| Geofencing | Client-side evaluation | Required for E2E encryption |
| Background location | Custom (geolocator + foreground service + sig-change) | No commercial dependency |
| Map | Platform maps (Google/Apple) or MapLibre | Best native experience, self-hosted option |
| TLS | Caddy reverse proxy | Auto Let's Encrypt, simple config |
| Federation addressing | user@server from day one | No migration needed when federation ships |
