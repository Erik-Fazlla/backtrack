# M0 field test — screen-off tracking

Goal: prove recording survives screen off + no signal before building anything else (SPEC §15, §16).

## Install
1. Phone: Settings → About → tap Build number 7× → Developer options → **USB debugging** on.
2. Plug phone into PC, accept the "Allow USB debugging" prompt.
3. In `D:\Projects\Owned\Backtrack`: `flutter install --release`
   (or copy `build\app\outputs\flutter-apk\app-release.apk` to the phone and open it).

## First launch
- Allow location **While using the app** (precise).
- Allow notifications (so the "Backtrack is recording" notification shows).
- Tap **Allow** on the battery banner → choose **Allow / Don't optimise**.
- Xiaomi / Samsung extra: Settings → Apps → Backtrack → Battery → **No restrictions** / **Unrestricted**.

## Test walk (60 min)
1. Outside, open the app, **airplane mode ON** (GPS still works).
2. Tap **Record**. Wait for "Waiting for GPS…" to turn into a line (may take 30 s–2 min without internet).
3. Lock the phone, pocket it. Walk ~60 min, include some trees/buildings.
4. Midway: unlock once, check the line is growing, lock again.
5. Optional kill test: swipe the app away from recents, reopen → trail should still be there and keep recording.
6. Tap **Stop**.

## Pass criteria
| Check | Pass if |
|---|---|
| Continuous line | No visible straight jumps across streets/fields |
| **Max gap** stat | ≤ 50 m |
| Distance | Within ~10% of what Google Maps/Strava says for the same route |
| Notification | "Backtrack is recording" visible the whole time |
| Battery | Note % used per hour (for M1 tuning) |

## Report back
Screenshot of the final screen (trail + stats), phone model, battery % used, anything odd.
