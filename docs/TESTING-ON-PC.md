# Testing Backtrack on the PC (no walk needed)

Three levels, fastest first.

## 1. Automated tests (seconds)

```powershell
flutter test
```

| Test file | What it proves |
|---|---|
| `test/core/geo_test.dart` | Distance maths is right (to ~1 m) |
| `test/core/point_filter_test.dart` | Bad-accuracy fixes and impossible jumps are dropped |
| `test/core/kalman_test.dart` | Jitter is smoothed; real movement followed without lag |
| `test/services/track_store_test.dart` | Points survive an app kill; half-written lines ignored |
| `test/services/recorder_test.dart` | Record → wait for GPS → record → stop → resume after kill |
| **`test/replay_test.dart`** | A 540 m walk around a block with **sharp 90° corners**, replayed with realistic GPS noise (±3 m) plus a 150 m jump and a bad fix. Checks: distance within 15%, no gap > 50 m, every saved point within 15 m of the true route, every corner kept within 8 m. |
| `test/widget_test.dart` | The screen: Record → points → Stop dialog → New recording |

## 2. Android emulator with a fake walk (minutes)

Runs the *real app* with the real GPS code; the emulator pretends to walk.

**One-time setup:** Android Studio → **Device Manager** → **+ Create Virtual Device** → Pixel (any) → a recent system image (with Google Play) → Finish. (~2 GB download.)

**Each test:**
1. Start the emulator, then in Android Studio press ▶ Run (or `flutter run`).
2. In the emulator side bar: **⋯ (Extended controls) → Location → Routes**.
3. **Import GPX/KML** → `test/fixtures/block_loop.gpx`.
4. In the app tap **Record**, then in Extended controls press **Play route** (speed 1× = walking, or 4×/8× to go faster).
5. Watch the orange line follow the block. Lock the emulator screen (power button in side bar) to test screen-off recording.

Make your own route: edit the corners in `tools/make_route.py`, then
```powershell
python tools/make_route.py > test/fixtures/my_route.gpx
```

## 3. Real phone (the final check)

Only real hardware shows real GPS behaviour under trees/buildings and the phone maker's battery killers. See `M0-FIELD-TEST.md`.
