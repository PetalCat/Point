# GlobalMap / Point — agent notes

## Repo layout

- `point/` — Flutter app (Android focus; iOS not a priority)
- `apk-server/` — Python HTTP server that hands out `point.apk` to Obtainium
- `scripts/rebuild-apk.sh` — builds the APK and pushes it to the remote app registry (10.10.10.14:8484)
- `website/` — SvelteKit marketing site

## Versioning

**Source of truth:** `point/pubspec.yaml` — the `version: X.Y.Z+build` line. That is the only file a human should edit to change the version.

**Generated / not tracked in git:**
- `apk-server/version.json` — written by `rebuild-apk.sh`, served to Obtainium. Gitignored.
- `apk-server/point.apk` — the built APK. Gitignored.

**How to ship a new APK:**

```
./scripts/rebuild-apk.sh
```

That script:
1. Reads build number from `apk-server/version.json` (or starts at 1)
2. Increments it, rewrites `pubspec.yaml` to `0.1.$BUILD+$BUILD`
3. Runs `flutter build apk --debug`
4. Copies the APK to `apk-server/point.apk`
5. Writes `apk-server/version.json` with the new version
6. Pushes APK + meta to the remote registry via `ssh docker@10.10.10.14`

After running: `pubspec.yaml` will be dirty (new version). Commit it with the feature work that motivated the rebuild. `apk-server/version.json` will also be updated on disk but is gitignored.

**Do not** manually edit `apk-server/version.json` — it gets clobbered. **Do not** commit it — it's in `.gitignore`.

## Map markers (high-DPI gotcha)

`point/lib/widgets/map_view.dart` renders person markers as custom bitmaps via `_getCircleIcon`. On Google Maps, `BitmapDescriptor.bytes(width: displaySize)` tells Google the logical size; Google rasterizes at `displaySize * devicePixelRatio` physical px. If the bitmap is rendered smaller than that it gets upscaled and looks blurry — the S24 Ultra (DPR 3.75) was hitting this.

Fix: `_getCircleIcon` takes a required `dpr` parameter, and `build()` passes `MediaQuery.devicePixelRatioOf(context).ceilToDouble()`. The icon cache clears when DPR changes, and `dpr` is part of the cache key. If you add a new marker type, thread `dpr` through the same way.

## Zone exit / background location

Handled by `point/lib/services/location_service.dart`, `zone_learning_service.dart`, and `native_geofence_service.dart`. The Android side registers OS-level geofences via `GeofencingClient` so doze mode can't kill them. There is also a 10-minute heartbeat (see recent commits on `main` for context). If background tracking breaks, check:
- Foreground service is alive (`c201bd9`)
- Heartbeat is firing (`3332ae5`)
- Geofence native channel `dev.petalcat.point/geofence` is wired up

## Testing

`flutter test` from `point/` runs the widget test. It wraps `PointApp` in `ProviderScope` — if you change `main.dart` to require additional scopes, update `test/widget_test.dart` accordingly.
