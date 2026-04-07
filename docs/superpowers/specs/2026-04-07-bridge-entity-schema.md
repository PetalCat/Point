# Bridge Entity Schema

## Core Principle

Every entity in Point — whether native or bridged — gets a Point address. The address is permanent, opaque (for bridged entities), and federation-ready. The bridge is just a SOURCE of data, not the identity.

## Addressing Design

Inspired by Beeper's approach (`@whatsapp_lid-12345:beeper.local`) but adapted for location sharing where items are shareable.

**Key decisions:**
- Native users: human-readable username (they chose to be here)
- Bridged entities: opaque UUID prefix (prevents guessing/probing)
- Bridge type is in the address (so you always know the source)
- Display names are metadata, NOT part of the address
- Even if you guess an address, server checks authorization before returning data

## Entity Types

### Native Person
A real Point user with their own account.
```
parker@point.petalcat.dev
```
- Has credentials, can log in
- Controls their own sharing/precision
- Fully autonomous
- Username is chosen by the user, visible to shared contacts

### Bridged Person  
Someone who exists on another platform, brought in by a user's bridge.
```
c7d2e8f0:findmy@point.petalcat.dev
```
Format: `<uuid8>:<bridge_type>@<server_domain>`

- `c7d2e8f0` — first 8 chars of a UUID v4 (opaque, unguessable)
- `findmy` — bridge type (non-sensitive, indicates data source)
- Display name "Mom" is metadata, not in the address
- Does NOT have a Point account
- Cannot log in or control settings
- Visible ONLY to bridge owner (NOT shareable — anti-surveillance)
- Shows a bridge badge in the UI

### Native Item
A tracker/thing managed directly in Point.
```
a4e9f1b2@point.petalcat.dev
```
- UUID-based address (opaque, like bridged entities)
- Display name "Car" is metadata
- Shareable to groups and individuals

### Bridged Item
A tracker from another platform, brought in by a bridge.
```
b7f3a2c1:airtag@point.petalcat.dev
e5d1c8a9:tile@point.petalcat.dev
```
Format: `<uuid8>:<tracker_type>@<server_domain>`

- Data comes from a bridge
- Bridge owner controls sharing
- Same sharing model as native items

## Bridge Ownership

Every bridged entity has a **bridge owner** — the Point user whose bridge provides the data.

```
Entity: mom:findmy@point.petalcat.dev
Bridge Owner: parker@point.petalcat.dev
Bridge Type: findmy
Source ID: "apple-id-hash-xyz" (opaque ID on the source platform)
```

The bridge owner:
- Controls who sees this entity (share to groups, individuals)
- Sets precision (exact/approximate/city)
- Can rename, delete, or unbridge the entity
- Is responsible for keeping the bridge running

## Federation Sharing

### Bridged items — fully shareable
```
parker@point.petalcat.dev shares keys:airtag@point.petalcat.dev 
  → with sarah@point.petalcat.dev (same server)
  → with alex@point.otherdomain.com (federated)
```
Items are objects you own. You decide who sees them. The remote server receives encrypted location blobs tagged with the item address. The bridge badge travels with the data.

### Bridged people — NOT shareable
```
parker@point.petalcat.dev CANNOT share mom:findmy@point.petalcat.dev
  → with anyone. Period.
```
Bridged people are visible only to the bridge owner. The server rejects any sharing attempt. This is enforced at the API level, not just the UI.

## Database Schema

### bridged_entities table
```sql
CREATE TABLE bridged_entities (
    -- Point identity
    id TEXT PRIMARY KEY,                    -- UUID
    address TEXT NOT NULL UNIQUE,            -- "mom:findmy@point.petalcat.dev"
    entity_type TEXT NOT NULL,              -- "person" or "item"
    display_name TEXT NOT NULL,             -- "Mom"
    
    -- Bridge info
    bridge_owner_id TEXT NOT NULL,          -- "parker@point.petalcat.dev"
    bridge_type TEXT NOT NULL,              -- "findmy", "google", "life360", "tile", etc.
    bridge_id TEXT,                         -- UUID of the bridge instance
    source_id TEXT,                         -- opaque ID on the source platform
    
    -- Item-specific (null for persons)
    tracker_type TEXT,                      -- "airtag", "tile", "smarttag"
    capabilities TEXT DEFAULT '[]',         -- JSON: ["ring", "lost_mode"]
    
    -- Location (encrypted)
    last_location BLOB,
    last_seen TEXT,
    
    -- Sharing (same model as native)
    -- Uses the existing item_shares table with this entity's ID
    
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### Sharing
Bridged entities use the SAME sharing tables as native items:
```sql
-- item_shares already exists
-- Works for both native items and bridged entities
INSERT INTO item_shares (item_id, target_type, target_id, precision) 
VALUES ('uuid-of-bridged-mom', 'group', 'family-group-uuid', 'exact');
```

### Bridge instances
```sql
-- bridges table already exists
-- Each bridge instance reports its discovered entities
-- Bridge owner confirms which ones to import into Point
```

## Entity Lifecycle

### Discovery
1. User runs a Find My bridge
2. Bridge authenticates to Apple, discovers: "Mom's iPhone", "Dad's iPhone", "Parker's AirTag - Keys"
3. Bridge reports to Point server: `item.discovered` messages
4. User sees discovered entities in the app, confirms which to import
5. Confirmed entities get a Point address: `mom:findmy@point.petalcat.dev`

### Ongoing Updates
1. Bridge periodically fetches locations from the source
2. Encrypts each location for the entity's shared recipients
3. Sends to Point server as `location.update` with the entity's address as sender
4. Server routes to recipients (same as any other location update)

### Unbridging
1. User removes a bridged entity
2. Point address is retired (can be reused later)
3. Bridge stops fetching for that entity
4. Shared recipients see it disappear

## Address Stability

An entity's Point address is STABLE:
- If the bridge restarts, the entity keeps its address (matched by source_id)
- If the bridge is moved to a different device, the entity keeps its address
- If the entity is shared with others, their references remain valid

The address only changes if:
- The user explicitly renames it
- The server domain changes

## Anti-Abuse (per safety spec)

### Bridged People — NOT shareable
- **Bridged persons are visible ONLY to the bridge owner.** They cannot be shared with any other Point user, group, or federated server.
- This prevents "surveillance laundering" — bridging someone's Find My location and re-distributing it to third parties who the person never consented to share with.
- The server enforces this: any attempt to share a bridged person entity returns 403 Forbidden.
- Bridged persons: map display for bridge owner only, NO geofence triggers, NOT federable.

### Bridged Items — shareable
- **Bridged items** (AirTags, Tiles, etc.) are shareable like native items. Items are objects you own — you decide who sees them.
- Geofence triggers allowed (items can't consent, owner decides)
- Cross-federation sharing allowed
- Bridge badge is non-removable

### Non-negotiable rules
- The bridge badge is **non-removable**: you can't disguise a bridged entity as native
- The entity_type ("person" vs "item") is **immutable**: you can't reclassify a bridged person as an item to bypass sharing restrictions
- These rules are enforced server-side, not just client-side

## Wire Format

Location updates for bridged entities look identical to native ones:
```json
{
    "type": "location.update",
    "sender": "mom:findmy@point.petalcat.dev",
    "recipients": ["group:family@point.petalcat.dev"],
    "encrypted_blob": "<base64>",
    "source_type": "bridge:findmy",
    "timestamp": 1712345678,
    "ttl": 300
}
```

The only difference from a native update is:
- `sender` is a bridged address (contains `:`)
- `source_type` starts with `bridge:`

Recipients decode these identically. The bridge badge is derived from the address format, not from any special flag.
