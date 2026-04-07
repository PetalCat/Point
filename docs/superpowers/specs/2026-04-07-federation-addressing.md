# Federation Addressing & Item Schema

## Addressing Format

All entities use a universal addressing format:

```
<local_id>@<domain>
```

### Users
```
parker@point.petalcat.dev
sarah@point.petalcat.dev
mom@findmy.point.petalcat.dev     ← bridged user (future)
```

### Items (Trackers)
```
keys:airtag@point.petalcat.dev
backpack:tile@point.petalcat.dev
car:smarttag@point.petalcat.dev
```

Format: `<name>:<tracker_type>@<domain>`

### Groups
```
family@point.petalcat.dev
friends@point.petalcat.dev
```

### Places (Geofences)
```
home@point.petalcat.dev
work@point.petalcat.dev
```

## Federation Model

When federation is implemented:

1. **User Discovery**: `parker@point.petalcat.dev` can share with `sarah@point.otherdomain.com`
2. **Server-to-Server**: Servers relay encrypted location blobs between federated users
3. **Trust**: Each server verifies the other via domain validation + key exchange
4. **Bridge Namespace**: Bridge sources are scoped to the originating server
   - `mom:findmy@point.petalcat.dev` — this server's Find My bridge found Mom
   - The bridge user doesn't exist on the remote server

## Item Schema (Detailed)

### Item Identity
```
id: UUID (internal)
address: "keys:airtag@point.petalcat.dev" (federation-ready)
owner_id: "parker@point.petalcat.dev"
name: "Keys"
tracker_type: "airtag" | "tile" | "smarttag" | "google" | "owntracks" | "manual"
source_id: "AIRTAG-SERIAL-123" (ID on source network)
bridge_id: UUID (which bridge provides updates)
```

### Item Location
```
last_location: encrypted blob (same format as person locations)
last_seen: timestamp
accuracy: meters
battery: percentage (some trackers report this)
```

### Item Sharing
Items follow the same sharing model as people:
- Share to a group: all members see it
- Share to a person: only they see it
- Precision control: exact / approximate / city
- Bridge items: source badge shows (Find My, Tile, etc.)

### Item Actions (bridge-dependent)
```
ring: bool       — can the bridge make it beep?
lost_mode: bool  — can the bridge flag it as lost?
directions: bool — always true (navigate to last known)
```

### Item Events
```
item.location    — position update (from bridge)
item.discovered  — bridge found a new tracker
item.alert       — moved, found, low battery
item.lost        — entered lost mode
```

## Server Domain Configuration

The server's domain (`point.petalcat.dev`) is used in ALL generated IDs:
- User IDs: `username@point.petalcat.dev`
- Item addresses: `name:type@point.petalcat.dev`
- Group IDs remain UUIDs (not federated yet)
- Place IDs remain UUIDs (not federated yet)

The domain is set via the `DOMAIN` environment variable.

## Migration Path

1. **Current**: All IDs use `@point.local` or `@<domain>` locally
2. **Federation v1**: Server-to-server relay for shares and location updates
3. **Federation v2**: Cross-server groups, federated item sharing
4. **Federation v3**: Bridge federation (share a bridge across servers)
