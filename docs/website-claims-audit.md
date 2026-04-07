# Website Claims Audit

Audit of every claim made on the Point marketing website vs actual implementation status.

## Legend
- ✅ TRUE — fully implemented and working
- ⚠️ PARTIAL — implemented but incomplete or untested
- ❌ FALSE — not yet implemented, claim should be removed or marked "coming soon"

---

## Home Page

| Claim | Status | Notes |
|-------|--------|-------|
| "E2E encrypted" | ❌ FALSE | MLS encryption (point-core crate) is NOT built. Currently uses base64 encoding, not encryption. The server CAN read location data right now. |
| "Self-hostable" | ✅ TRUE | Docker deployment works, tested on 10.10.10.14 |
| "Bridge Find My, Google Maps, Life360, Tile" | ❌ FALSE | No bridges are built yet. Only the bridge registry and entity schema exist. |
| "OwnTracks" bridge | ❌ FALSE | MQTT ingestion not implemented yet |
| "SmartTag" bridge | ❌ FALSE | Not implemented |
| "Real-time Location" | ✅ TRUE | WebSocket location sharing works e2e |
| "Battery level and speed included" | ✅ TRUE | Battery and speed display working |
| "Zero-knowledge server design" | ❌ FALSE | Server CAN read locations currently (no encryption) |
| "Geofencing - circle and polygon" | ✅ TRUE | Both work with client-side evaluation |
| "Push notifications when people arrive or leave" | ⚠️ PARTIAL | FCM wake-up pushes work, but geofence alerts only fire when YOUR app is open |
| "Ghost Mode" | ✅ TRUE | Toggle works, stops sending |
| "No one knows you went dark" | ⚠️ PARTIAL | Others see you as "not sharing" which is a hint |
| "Heatmap history" | ⚠️ PARTIAL | History API exists, heatmap screen built, but minimally tested |
| "Groups & 1:1" | ✅ TRUE | Both work with share requests |
| "Temporary share links that auto-expire" | ✅ TRUE | Working with TTL cleanup |
| "Self-Hostable with Docker" | ✅ TRUE | Working |
| "Federation-ready" | ⚠️ PARTIAL | Addressing uses user@domain format, but no actual server-to-server federation exists |
| "Anti-Surveillance - Bridged people can't be shared" | ✅ TRUE | Server returns 403 when trying to share bridged persons |
| "Open Source" | ⚠️ PARTIAL | Code exists but no public GitHub repo yet |

## Features Page

| Claim | Status | Notes |
|-------|--------|-------|
| "Sub-second position updates" | ❌ FALSE | Updates every 10 seconds typically |
| "Precision control (exact / neighborhood / city)" | ⚠️ PARTIAL | Server supports it, UI for setting exists, but approximate/city map visualization may not be fully working |
| "Dark mode optimized map" | ✅ TRUE | Google Maps MapColorScheme.dark tied to app theme |
| "Device-side encryption" | ❌ FALSE | No encryption exists yet — just base64 |
| "Forward secrecy for location data" | ❌ FALSE | MLS not implemented |
| "Open source & auditable" | ⚠️ PARTIAL | Code exists but no public repo |
| "Circle & polygon geofences" | ✅ TRUE | Both working |
| "Per-person geofence alerts" | ⚠️ PARTIAL | Zone consent system built but untested |
| "No limit on active geofences" | ⚠️ PARTIAL | Server has no limit, but iOS/Android OS limits apply (20/100) |
| "Scheduled ghost mode" | ❌ FALSE | Only manual toggle exists, no schedule |
| "Per-group ghost settings" | ⚠️ PARTIAL | Server has per-group sharing toggle, but no per-group ghost UI |
| "Animated trail playback" | ❌ FALSE | Live 30-min trails exist, but no playback of historical trails |
| "Date range filtering" | ⚠️ PARTIAL | History API supports since/limit, heatmap has 24h/7d/30d pills |
| "Unlimited groups" | ✅ TRUE | No server-side limit |
| "Role-based permissions" | ✅ TRUE | admin/member/viewer roles working |
| "Apple Find My bridge" | ❌ FALSE | Not built |
| "Google Maps bridge" | ❌ FALSE | Not built |
| "Life360 bridge" | ❌ FALSE | Not built |
| "Tile / SmartTag bridge" | ❌ FALSE | Not built |
| "OwnTracks bridge" | ❌ FALSE | Not built |
| "Open bridge API for community-built integrations" | ⚠️ PARTIAL | Bridge entity API exists, but no documentation or SDK |

## Privacy Page

| Claim | Status | Notes |
|-------|--------|-------|
| "Zero-Knowledge Server" | ❌ FALSE | Server can read all data currently |
| "End-to-End Encryption" | ❌ FALSE | Not implemented |
| "Anti-Surveillance by Design" | ✅ TRUE | Bridged person sharing blocked, safety spec documented |
| "Ghost mode is silent" | ✅ TRUE | No notification sent to others |
| "Self-hostable" | ✅ TRUE | Docker works |
| "Every line of code is public" | ❌ FALSE | No public repo yet |
| "No analytics, no trackers, no advertising" | ✅ TRUE | None exist in the codebase |
| "No data sales" | ✅ TRUE | No data collection or sales |

## Self-Host Page

| Claim | Status | Notes |
|-------|--------|-------|
| "Up and running in 60 seconds" | ⚠️ PARTIAL | Docker works but first build takes longer |
| "POINT_FEDERATION=true" | ❌ FALSE | Federation env var does nothing — federation not implemented |
| "Runs on a Raspberry Pi" | ⚠️ PARTIAL | Probably works (Rust is efficient) but untested on ARM |
| "Federation - Connect your instance to others" | ❌ FALSE | Not implemented |
| "Auto Updates" | ⚠️ PARTIAL | Watchtower would work but not tested/documented |

## Download Page

| Claim | Status | Notes |
|-------|--------|-------|
| "Android 8.0 or later" | ⚠️ PARTIAL | Probably true but not tested on Android 8 |
| "Fully open source build available on F-Droid" | ❌ FALSE | Not on F-Droid |

---

## Summary

| Status | Count |
|--------|-------|
| ✅ TRUE | 15 |
| ⚠️ PARTIAL | 14 |
| ❌ FALSE | 17 |

## Critical Claims to Fix

The biggest false claims that should be addressed:

1. **"E2E Encrypted" / "Zero-Knowledge Server"** — This is the #1 claim and it's completely false. The server sees everything in plaintext. Either implement MLS or change the claim to "designed for E2E encryption" / "E2E encryption coming soon."

2. **All bridge claims** — No bridges exist. Either remove the bridge section or clearly mark everything as "coming soon."

3. **"Open source"** — No public repo. Either publish it or don't claim it.

4. **"Federation"** — Not implemented. Remove or mark as roadmap.

5. **"Sub-second position updates"** — Updates are every 10 seconds.

## Recommended Actions

1. Add "Coming Soon" badges to all bridge logos
2. Change E2E claims to "Designed for E2E encryption" or add a roadmap disclaimer
3. Add a "Roadmap" section showing what's built vs planned
4. Mark federation as "planned" not "available"
5. Remove the POINT_FEDERATION env var from the self-host page
6. Add a beta disclaimer to the download page
