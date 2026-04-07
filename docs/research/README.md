# Point Research

Deep research conducted before spec/implementation. Each report covers a major technical question.

## Reports

| # | File | Topic | Key Findings |
|---|------|-------|-------------|
| 1 | [01-bridge-feasibility.md](01-bridge-feasibility.md) | Bridge feasibility per service | All bridges are reverse-engineered and fragile. Find My, Google, Life360 feasible but breakable. Snap Map near-impossible. WhatsApp hostile to unofficial clients. |
| 2 | [02-mls-and-flutter-rust-ffi.md](02-mls-and-flutter-rust-ffi.md) | MLS (OpenMLS) + Rust/Flutter FFI | OpenMLS is production-ready (Wire, Matrix use it). Flutter Rust Bridge handles async/streams. ~100ns FFI overhead. Shared Rust crate for server+client. |
| 3 | [03-snapmap-reverse-engineering.md](03-snapmap-reverse-engineering.md) | Snap Map reverse engineering | gRPC "MUSHROOM" protocol, aggressive cert pinning, no public schemas. Feasible with Frida but will break on every update. Separate project, not MVP-blocking. |
| 4 | [04-realtime-protocol-design.md](04-realtime-protocol-design.md) | Custom real-time location protocol | Protobuf encoding, Axum+Tokio WebSockets (~200K conn/instance), adaptive update rates, exponential backoff reconnection, federation-ready namespaced IDs. |
| 5 | [05-self-hosted-deployment-owntracks.md](05-self-hosted-deployment-owntracks.md) | Self-hosted deployment + OwnTracks | OwnTracks MQTT JSON format documented. Single-binary Rust deployment. Docker Compose stack. Caddy for auto-TLS. First-user-is-admin onboarding. |
| 6 | [06-geofencing-architecture.md](06-geofencing-architecture.md) | Geofencing architecture | Client-side evaluation required for E2E. iOS: 20 regions, Android: 100. Virtual geofencing for overflow. Fence definitions shared as encrypted group content. |
| 7 | [07-unified-location-hub-vision.md](07-unified-location-hub-vision.md) | Expanded vision: location super-app | Place search, route comparison, ride booking, item trackers, location inbox, map memory. API feasibility matrix. |
