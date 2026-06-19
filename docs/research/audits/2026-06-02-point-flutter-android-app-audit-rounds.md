# Point Flutter/Android App Audit Rounds

Artifact: `point` Flutter/Android app source audit for bugs, feature issues, and style.
Reviewer: Codex.
Cadence: append one entry per audit round against the reviewed commit.

## Round 1 - Codex

Spec commit reviewed: `ac3907c`
Verdict: NO-GO
Findings count + severity breakdown: 18 findings (8 BLOCKING, 7 SHOULD-FIX, 3 NICE-TO-HAVE)

Findings:

1. Claim: The group "Share Location" toggle does not stop local group relay.
   Evidence: `point/lib/screens/group_detail_screen.dart:133`, `point/lib/screens/group_detail_screen.dart:617`, `point/lib/screens/home_screen.dart:95`, `point/lib/providers/location_provider.dart:590`.
   Severity: BLOCKING.
   Suggested change: Derive active group relay IDs from group membership `sharing == true`, update `LocationNotifier` after settings changes, and stop relay immediately when disabled.

2. Claim: Background tracking/batching hooks are defined but unreachable.
   Evidence: `point/lib/services/location_service.dart:158`, `point/lib/services/location_service.dart:183`, `point/lib/providers/location_provider.dart:796`; `rg` finds no lifecycle callers.
   Severity: BLOCKING.
   Suggested change: Add a `WidgetsBindingObserver` or native lifecycle bridge that calls both `LocationService.appOpened/appBackgrounded` and `LocationNotifier.setBackgrounded`.

3. Claim: WebSocket disconnects silently drop foreground and buffered location updates.
   Evidence: `point/lib/services/ws_service.dart:81`, `point/lib/providers/location_provider.dart:545`, `point/lib/providers/location_provider.dart:594`, `point/lib/services/relay_buffer.dart:30`, `point/lib/providers/location_provider.dart:655`.
   Severity: BLOCKING.
   Suggested change: Queue unsent messages or keep relay buffer entries until `WsService` confirms send on an authenticated open connection.

4. Claim: MLS encryption is bypassed when a group/pairwise MLS session is missing.
   Evidence: `point/lib/services/crypto_service.dart:201`, `point/lib/services/crypto_service.dart:211`, `point/lib/providers/location_provider.dart:615`.
   Severity: BLOCKING.
   Suggested change: Do not transmit location plaintext/base64 fallback for production relay; surface MLS setup failure and retry key exchange.

5. Claim: Ghost timers/global ghost are not persisted and background ghost evaluation ignores timers.
   Evidence: `point/lib/providers/ghost_provider.dart:146`, `point/lib/providers/ghost_provider.dart:337`, `point/lib/providers/ghost_provider.dart:343`, `point/lib/providers/ghost_provider.dart:18`.
   Severity: BLOCKING.
   Suggested change: Persist manual global/timer state, restore it on startup, and make background callbacks evaluate timer expiry as well as rules.

6. Claim: Learned zones load too late for cold-start geofence re-registration.
   Evidence: `point/lib/providers/location_provider.dart:253`, `point/lib/providers/location_provider.dart:359`, `point/lib/screens/home_screen.dart:56`.
   Severity: BLOCKING.
   Suggested change: Load `ZoneLearningService` before `LocationNotifier` performs `_fetchInitialPosition`, or re-run restart zone registration after load completes.

7. Claim: Learned-zone entry relays exact current GPS despite claiming to relay zone center.
   Evidence: `point/lib/providers/location_provider.dart:415`, `point/lib/providers/location_provider.dart:561`.
   Severity: BLOCKING.
   Suggested change: Send a deliberately coarse zone-center payload/source type on entry, then suppress exact fixes while in-zone.

8. Claim: Push wake/nudge handling is not wired.
   Evidence: `point/lib/main.dart:50`, `point/lib/screens/home_screen.dart:84`, `point/lib/services/push_service.dart:57`, `point/lib/services/push_service.dart:90`.
   Severity: BLOCKING.
   Suggested change: Pass an `onMessage` handler that routes push nudge/location events to `LocationService.wake`, and make the background FCM handler process data messages.

9. Claim: Temporary share creation does not refresh state, start local relay, or set up direct MLS.
   Evidence: `point/lib/screens/tabs/sharing_tab.dart:1131`, `point/lib/providers/sharing_provider.dart:218`, `point/lib/screens/home_screen.dart:142`.
   Severity: SHOULD-FIX.
   Suggested change: Add temp shares to state/UI, call `loadAll`/`listTempShares`, update `activeUserIds`, and establish pairwise MLS before first relay.

10. Claim: Incoming zone consent requests count toward the badge but are not rendered/actionable.
    Evidence: `point/lib/providers/sharing_provider.dart:25`, `point/lib/screens/tabs/sharing_tab.dart:309`, `point/lib/screens/tabs/inbox_tab.dart:31`.
    Severity: SHOULD-FIX.
    Suggested change: Render incoming zone consents in Sharing/Inbox with accept/reject mutations.

11. Claim: Several mutations swallow provider errors, so UI mutations report success even when nothing changed.
    Evidence: `point/lib/providers/sharing_provider.dart:134`, `point/lib/providers/sharing_provider.dart:163`, `point/lib/screens/tabs/sharing_tab.dart:725`.
    Severity: SHOULD-FIX.
    Suggested change: Re-throw after updating local error state or return explicit failure values consumed by the mutation.

12. Claim: Place Arrive/Leave toggles are UI-only.
    Evidence: `point/lib/screens/place_creation_screen.dart:25`, `point/lib/screens/place_creation_screen.dart:504`, `point/lib/screens/place_creation_screen.dart:80`, `point-server/src/api/places.rs:102`.
    Severity: SHOULD-FIX.
    Suggested change: Send selected triggers to the API and respect them in local/server geofence evaluation.

13. Claim: "Notify when nearby" is a visible no-op.
    Evidence: `point/lib/screens/tabs/sharing_tab.dart:542`.
    Severity: SHOULD-FIX.
    Suggested change: Implement proximity alert setup or remove/disable the action until supported.

14. Claim: "Find on map" only switches tabs; it does not select or follow the person.
    Evidence: `point/lib/screens/tabs/sharing_tab.dart:538`, `point/lib/screens/home_screen.dart:180`.
    Severity: SHOULD-FIX.
    Suggested change: Pass the selected user ID back to HomeScreen and call the existing select/follow path.

15. Claim: Permission-denied location startup fails silently.
    Evidence: `point/lib/providers/location_provider.dart:346`, `point/lib/services/location_service.dart:89`, `point/lib/services/location_service.dart:104`.
    Severity: SHOULD-FIX.
    Suggested change: Surface denied/disabled location services with a prompt, settings shortcut, and visible inactive state.

16. Claim: Riverpod lint is configured in an invalid analyzer section.
    Evidence: `point/analysis_options.yaml:3`; `flutter analyze` reports `Invalid format for the 'plugins' section`.
    Severity: NICE-TO-HAVE.
    Suggested change: Move plugin config to the analyzer-supported shape for the installed analyzer/Riverpod lint versions.

17. Claim: `ref.listen` is registered from `build`.
    Evidence: `point/lib/screens/tabs/sharing_tab.dart:29`.
    Severity: NICE-TO-HAVE.
    Suggested change: Move listeners to `initState`/manual subscriptions or an effect-style lifecycle hook.

18. Claim: `LocationNotifier` mixes relay, cache, WS, zones, geofences, ghost checks, and UI event generation in one large notifier.
    Evidence: `point/lib/providers/location_provider.dart:172`, `point/lib/providers/location_provider.dart:509`, `point/lib/providers/location_provider.dart:1159`.
    Severity: NICE-TO-HAVE.
    Suggested change: Split relay transport, zone state, place geofence evaluation, and cache persistence into focused services with typed payloads.

Closures landed in commit `<sha>`: none; first audit round.
