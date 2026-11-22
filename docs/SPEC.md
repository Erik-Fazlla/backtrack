# Backtrack — Product & Technical Spec

_Name: Backtrack (final). Status: draft v2 · 2026-11-22 · Owner: Erik · Personal use_

## 1. One-liner

Press **Record** when you leave the trail head. Walk anywhere. Press **Stop** and the app shows the exact line you walked, your live position on it, and an arrow home — **with zero signal and zero internet**.

## 2. Problem

People get lost in forests, mountains and unfamiliar terrain because:
- There is no phone signal, so Google Maps shows a grey screen.
- Paths look different on the way back.
- Full outdoor apps (OsmAnd, Gaia, AllTrails) are heavy, paid, or bury the breadcrumb feature.

**Backtrack does one job: get you back the way you came.**

## 3. Constraints

| Constraint | Consequence |
|---|---|
| **$0 budget** | Only free / open-source packages. No paid SDKs, no paid map APIs, no servers we pay for. |
| **Fully offline at use time** | All core features run with airplane mode on. Internet only used *before* a trip (optional map download). |
| **Personal use** | No store publishing. Android APK installed directly on Erik's phone (`flutter install` / sideload). No store fees, no review process. |
| **Android only (for now)** | iOS would need a Mac + Apple account. Flutter keeps that door open if ever needed. |
| **Private repo** | GitHub `Erik-Fazlla/backtrack`, private. |

## 4. Why it works offline (core fact)

GPS receivers listen to satellites directly — no cell or data connection needed. Internet only helps two things:
1. **Fast first fix (A-GPS).** Without it, first fix can take 30 s – few min. *Mitigation:* app shows "Waiting for GPS…" with accuracy, and Record only starts the trail once accuracy ≤ 30 m. Tip in onboarding: open the app before losing signal.
2. **Map imagery.** Without it the trail draws on a plain grid. *Mitigation:* optional offline map download (§9).

## 5. Users & core scenarios

- **Forest walker** — goes off-trail mushroom picking, wants to find the car again.
- **Hiker** — repeats a favourite trail; saved journey shows the route next time.
- **Traveller** — walks around an unfamiliar town with no roaming data, needs to get back to the hotel.

### Scenario A — Record & return (the core loop)
1. Open app → GPS fixes → tap **Record**.
2. Phone in pocket, screen off. Trail keeps recording (foreground service + notification).
3. Tap **Stop** (or **Take me back**).
4. Map shows full trail, start marker, live position, arrow + distance to start.
5. Walk back. If drifting > 30 m off the trail, phone vibrates.
6. Reach start → "You're back" → offered to **Save** the journey with a name.

### Scenario B — Save & reuse
1. After a journey, user names it ("Pine forest loop"), picks a category (Hike) and saves it on the phone.
2. Weeks later: **Library** (filter: Hikes) or **Map view** (tap the line) → open it → **Follow this trail**.
3. Live position shown on the saved line, off-trail alerts on, progress % shown.

### Scenario C — Hike with hills
1. Recording a hike. Screen shows current altitude and "↑ uphill 8%" / "↓ downhill 5%".
2. After Stop: elevation profile chart shows climbs and descents, total gain / loss, highest / lowest point.
3. When following a saved hike: profile shows "you are here" and what is still ahead ("+120 m climb left").

### Scenario D — Browse my journeys on the map
1. Open **Map view**: every saved journey drawn as a line in its category colour (like the red loops over Athens streets).
2. Tap a line → bottom sheet: name, category, date, distance, duration, elevation gain → **Details** / **Follow**.

## 6. Features

### MVP (v0.1) — must work perfectly before anything else
| # | Feature | Detail |
|---|---|---|
| F1 | **Record trail** | Start / Pause / Stop. Records with screen off and app backgrounded. |
| F2 | **Live trail line** | Orange line grows as you move (Strava style). Start marker. |
| F3 | **Back-to-start arrow** | Big arrow pointing to start + straight-line distance ("1.4 km"). Uses compass heading. |
| F4 | **Follow-back mode** | After Stop: trail stays on screen, live dot on it, map rotates with heading (toggle). |
| F5 | **Off-trail alert** | Vibrate + banner when > 30 m from the nearest trail segment for > 10 s (debounced). |
| F6 | **Save journey** | Name, **category**, auto date, distance, duration, elevation gain/loss. Stored locally on the phone. |
| F7 | **Library (list view)** | All saved journeys as cards. **Filter by category** (Run, Hike, Walk, Bike, Other + user-made), date range, distance range. Search by name. Sort by date / distance / elevation gain. Open, rename, change category, delete. |
| F8 | **Map view of journeys** | All saved journeys drawn on one map, coloured by category (respects the same filters). **Tap a line** → bottom sheet with name, category, date, distance, duration, elevation gain → Details / Follow. Overlapping lines: tap picks nearest; if several within tap radius, show a small chooser. |
| F9 | **Follow a saved journey** | Load saved trail as the guide line; same F3–F5 behaviour. Arrow targets start *or* end (user picks). |
| F10 | **Elevation tracking** | Live altitude, live grade with ↑ uphill / ↓ downhill / → flat indicator. Per journey: total gain, total loss, max / min altitude. **Elevation profile chart** (distance × altitude) on journey details; when following, profile marks current position and climb remaining. |
| F11 | **GPS status** | Accuracy indicator, "Waiting for GPS…", warning when accuracy poor. |
| F12 | **Crash-safe recording** | Points written to DB as they arrive; if app is killed, recording resumes / is recoverable on relaunch. |

### v0.2
| # | Feature |
|---|---|
| F13 | **Offline map download** for a region (§9). |
| F14 | **Return progress** — "62% of the way back", distance remaining *along the trail* (not straight line). |
| F15 | **Battery guard** — warns when battery % is lower than estimated needed for return at current drain. |
| F16 | **Battery saver mode** — longer interval between points. |
| F17 | **Waypoints** — drop a pin ("car", "junction", "water") while recording. |
| F18 | **Trail coloured by grade** — optional: line colour shows steepness (green flat → red steep). |
| F18a | **Settings & appearance** — light/dark map, app theme, category + trail colours (§13a). |
| F18b | **Region import** — Stage 1 offline map process (§9). |

### v0.3+
| # | Feature |
|---|---|
| F19 | GPX export / import (share a trail with a friend, open in other apps). |
| F20 | More stats per journey (pace splits, moving vs stopped time). |
| F21 | Turn-around reminder (time or distance based). |
| F22 | Dark / high-contrast "low light" theme. |
| F22a | **In-app region download** — Stage 2 offline map process (§9). |
| F23 | Offline terrain data (Mapterhorn DEM PMTiles) to correct elevation on phones without a barometer. |

### Out of scope (explicitly)
Accounts, cloud sync, social feed, turn-by-turn routing, search for addresses. Everything stays on the phone.

## 7. Tech stack (all free)

| Concern | Choice | License / cost | Notes |
|---|---|---|---|
| Framework | **Flutter** (Dart) | BSD, free | Matches device-feature stack rule. |
| Tooling | **Android Studio** (Android SDK, emulator, device logs) + Flutter plugin; code editing in Android Studio or VS Code | free | Builds run with `flutter run` onto Erik's phone over USB/Wi-Fi debugging. |
| Location | **geolocator** | MIT, free | Android `foregroundNotificationConfig` keeps stream alive with screen off. *Not* `flutter_background_geolocation` (paid licence for Android release). |
| Wake / service hardening | Android foreground service type `location`, battery-optimization exemption prompt | free | Needed against Doze / OEM killers (Xiaomi, Samsung). |
| Compass | **flutter_compass** | MIT | Heading for arrow + map rotation. Fallback to GPS bearing when moving. |
| Map widget | **flutter_map** | BSD | Pure Dart, works with no tiles at all (trail on grid). |
| Offline vector map | **vector_map_tiles** + **vector_map_tiles_pmtiles** | MIT/BSD | Renders a local `.pmtiles` file. |
| Map data | **Protomaps basemap** (OpenStreetMap) | ODbL, free | Attribution "© OpenStreetMap contributors" required. |
| Storage | **drift** (SQLite) | MIT | Journeys + points. |
| State mgmt | **Riverpod** | MIT | |
| Vibration | **vibration** / HapticFeedback | free | Off-trail alert. |
| Battery | **battery_plus** | BSD | F15. |
| Barometer | **sensors_plus** (pressure sensor) | BSD | Better elevation *changes* than GPS altitude (§11a). Optional: not every phone has one. |
| Charts | **fl_chart** | MIT | Elevation profile. |
| Polyline tap | flutter_map `PolylineLayer` hit detection (`hitNotifier`) | BSD | F8 tap-a-line. |
| Permissions | **permission_handler** | MIT | |
| CI | GitHub Actions (free tier) | free | Tests + build APK. |

## 8. Architecture

```
lib/
  core/            theme, constants, geo math (haversine, point-to-segment distance)
  data/
    db/            drift schema + DAOs
    repositories/  JourneyRepository, PointRepository, MapRegionRepository
  services/
    location_service.dart     geolocator stream, filtering, foreground service
    heading_service.dart      compass + bearing fallback
    elevation_service.dart    GPS altitude + barometer fusion, grade, gain/loss
    trail_guide.dart          off-trail detection, distance-to-start, progress
    recording_controller.dart state machine: idle → waitingForFix → recording ⇄ paused → stopped
  features/
    record/        record screen (map + controls + arrow)
    follow/        follow-back / follow-saved screen
    library/       list view: filters, search, sort, categories
    journey_map/   map view of all journeys, tap-a-line bottom sheet
    journey_detail/ stats, elevation profile, rename/category/delete, follow
    maps/          offline region download / manage
    settings/
```

Layers: UI → controllers (Riverpod) → services → repositories → drift. Geo math is pure Dart and fully unit-tested.

### Recording state machine
`idle → waitingForFix (accuracy ≤ 30 m) → recording ⇄ paused → stopped → (saved | discarded)`
Recovery: on launch, an unfinished journey in DB → "Resume recording or finish it?"

## 9. Offline maps at $0 — the plan

**What a "region" means:** an offline map of the whole world is ~120 GB, too big for a phone. So the map is cut into areas ("regions") — e.g. *Attica*, *Greece*, *Peloponnese*. You download only the region you'll be in, before you go, while you still have Wi-Fi. **First region: Greece** (size to be measured; expected a few hundred MB at max zoom 15).

### Getting a new region (e.g. trip to Italy)

**Stage 1 (v0.2) — PC script + import.** Repo is private, so the app can't download from its GitHub Releases without a token; keep it simple:
1. On PC: `tools/cut_region.ps1 -Name italy -Country IT` (or `-Bbox minLon,minLat,maxLon,maxLat`). Script runs the free `pmtiles extract` against the latest Protomaps daily build and writes `italy.pmtiles`. Only the needed bytes are downloaded, not the planet.
2. Copy the file to the phone (USB cable, or Google Drive / any cloud you already use).
3. In app: **Settings → Offline maps → Import map file** → pick `italy.pmtiles`. App copies it into its storage, reads its bounds, lists it.
4. Map automatically uses whichever downloaded region covers where you are.

**Stage 2 (v0.3) — download inside the app, no PC.**
1. **Settings → Offline maps → Add region** → pick a country from a built-in list, *or* pan the map and drag a rectangle ("download this area").
2. App shows estimated size → **Download** (Wi-Fi recommended, resumable).
3. App fetches only the tiles inside that area straight from the free Protomaps daily build (HTTP range requests, same thing `pmtiles extract` does) and saves them as a local region file.
- Low-volume personal use; if Protomaps' terms or availability change, Stage 1 still works.

**Managing regions:** list with name, size, map date; **Update** (re-download newer data) and **Delete** to free space.

**Rule:** never bulk-download from `tile.openstreetmap.org` — its usage policy forbids it.

**Approach — PMTiles region files:**
1. Protomaps publishes a free daily planet build (`build.protomaps.com/YYYYMMDD.pmtiles`, ODbL).
2. Erik cuts region files on his PC with the free `pmtiles extract <planet-url> greece.pmtiles --bbox=...` CLI (HTTP range requests, no full planet download).
3. Region files are hosted as **GitHub Release assets** (free; ≤ 2 GB per file).
4. App has a **Maps** screen: list of available regions (a JSON index in the repo) → download → stored on device → rendered offline by `vector_map_tiles_pmtiles`.
5. Also: **Import .pmtiles file** from phone storage (power users / any region).

Start with 1–3 regions (e.g. Greece). Max zoom ~15 keeps files small (country = tens to a few hundred MB).

**Later (v0.3+, optional):** in-app "download this visible area" by implementing PMTiles bbox extraction in Dart against a self-chosen source. Only if hosting stays $0 and source terms allow it.

**No map downloaded?** App still fully works — trail on a light grid with scale bar and north arrow. This is the guaranteed baseline.

## 10. Data model (drift)

```
categories
  id            INTEGER PK
  name          TEXT      -- seeded: Run, Hike, Walk, Bike, Other; user can add
  color         INTEGER   -- line colour on map view
  icon          TEXT

journeys
  id            INTEGER PK
  name          TEXT
  category_id   FK → categories
  status        TEXT  -- recording | paused | finished
  started_at    DATETIME
  ended_at      DATETIME NULL
  distance_m    REAL
  duration_s    INTEGER   -- excludes paused time
  elevation_gain_m REAL
  elevation_loss_m REAL
  max_altitude_m   REAL
  min_altitude_m   REAL
  bbox_min_lat, bbox_min_lon, bbox_max_lat, bbox_max_lon REAL  -- fast map-view culling
  simplified_line  BLOB   -- Douglas-Peucker simplified polyline for map view (fast drawing of many journeys)
  saved         BOOL      -- false = unsaved/temporary, auto-cleaned after 7 days

track_points
  id            INTEGER PK
  journey_id    FK → journeys
  seq           INTEGER
  lat, lon      REAL
  altitude_m    REAL NULL   -- fused/smoothed altitude (§11a)
  gps_altitude_m REAL NULL  -- raw GPS altitude
  pressure_hpa  REAL NULL   -- raw barometer reading, if phone has one
  accuracy_m    REAL
  speed_mps     REAL NULL
  recorded_at   DATETIME
  INDEX (journey_id, seq)

waypoints        (v0.2)
  id, journey_id, lat, lon, label, icon, created_at

map_regions      (v0.2)
  id, name, file_path, bbox, size_bytes, source_date, downloaded_at
```

Storage estimate: 1 point / 5 m ≈ 200 pts/km ≈ ~10 KB/km. A 20 km hike ≈ 200 KB. Thousands of journeys fit easily.

## 11. GPS quality rules

| Rule | Value (tunable) |
|---|---|
| Distance filter | Record a point every **5 m** moved (battery saver: 15 m) |
| Reject point if accuracy worse than | **25 m** |
| Reject jump | implied speed > **15 m/s** on foot (spike) |
| Smoothing | light moving-average / simple Kalman on display line; raw points kept in DB |
| Stationary | no new points when not moving (distance filter handles it) |

## 11a. Elevation rules

GPS altitude alone is noisy (±10–20 m jumps), which would show fake hills and inflate gain. Approach:

| Step | Rule |
|---|---|
| Source | If phone has a **barometer**: use pressure for *changes* in altitude (precise to ~1 m), anchored to GPS altitude averaged over the first minute. No barometer: GPS altitude only, heavier smoothing. |
| Smoothing | Moving average over ~30 m of distance. |
| Gain / loss | Count only changes beyond a **3 m threshold** (hysteresis) — ignores noise wiggles. |
| Grade | rise ÷ run over the last **50 m** walked. Shown as ↑ uphill when > +3%, ↓ downhill when < −3%, → flat otherwise. |
| Display | Current altitude (m), grade %, arrow. Profile chart on details screen. |
| Test | Replay fixtures with known climbs; assert gain within ±10% of reference. |

## 12. Off-trail & guidance logic

- **Distance to trail** = min point-to-segment distance from live position to the guide polyline (search window around last matched segment for speed).
- **Off-trail** if > 30 m for > 10 s → vibrate pattern + red banner "Off trail — 45 m. Trail is to your left." Clears when back < 20 m (hysteresis).
- **Arrow** = bearing(live → target) − device heading.
- **Progress** = along-trail distance of matched segment ÷ total trail length.

## 13. Permissions (Android)

- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION` (asked separately, with explanation screen — required by Android 10+)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS` (Android 13+)
- `VIBRATE`
- `INTERNET` (map download only)
- Prompt to disable battery optimization for the app (explain why).

Privacy: no data leaves the phone. No analytics. State this in onboarding.

## 13a. Settings & appearance

| Setting | Options | Default |
|---|---|---|
| **Map style** | Light · Dark (Protomaps `light` / `dark` themes; also usable: white, grayscale, black) | Light |
| **App theme** | Light · Dark · Follow system | Follow system |
| **Category colours** | Colour picker per category (Run, Hike, …). Used for lines in Map view and library chips. | Run orange · Hike green · Walk blue · Bike purple · Other grey |
| **Live trail colour** | Colour picker for the line being recorded | Orange |
| **Guide line colour** | Colour of a saved trail you are following | Category colour |
| Units | Metric · Imperial | Metric |
| Off-trail distance | 20 / 30 / 50 m | 30 m |
| GPS interval | Normal (5 m) · Battery saver (15 m) | Normal |
| Offline maps | Import / add / update / delete regions (§9) | — |

Rules: no-map grid background follows the map style (light grid / dark grid). Colour pickers offer a preset palette checked for contrast on both light and dark maps, plus custom. Settings stored locally (drift `settings` table or shared_preferences).

## 14. UX principles

- **One big button.** Record is the home screen hero.
- Readable in sunlight, usable with gloves: large touch targets (≥ 56 dp), high contrast.
- Orange trail line, blue live dot, green start marker.
- Calm, safety-first copy. Never alarming unless truly off trail or low battery.
- Works one-handed.

## 15. Testing strategy

| Level | What |
|---|---|
| Unit (TDD) | Geo math, point filtering, off-trail detection, progress, state machine. |
| Widget | Record screen states, journeys list, save dialog. |
| Replay tests | Feed recorded GPX fixtures (incl. noisy forest data) through the pipeline, assert trail + alerts. |
| Device (Erik) | Real walk with airplane mode on, screen off 30+ min, on at least one aggressive-OEM phone. |

**Go/no-go gate for v0.1:** a 60-minute walk, airplane mode, screen off, produces a continuous trail with no gaps > 50 m, and follow-back gets you to start.

## 16. Milestones

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 — Tracking spike** | Bare app: record points with screen off, draw on blank canvas. | Passes §15 gate on Erik's phone. **If this fails, stop and fix before anything else.** |
| **M1 — MVP v0.1** | F1–F12 | All unit/widget tests green; real-walk test passes; a real hike shows a believable elevation profile. Installed on Erik's phone. |
| **M2 — v0.2** | F13–F18, offline maps | Greece (or Attica) region rendering offline in airplane mode. |
| **M3 — v0.3** | F19–F23 | GPX round-trip with another app. |

## 17. Risks

| Risk | Mitigation |
|---|---|
| OEM battery killers stop recording | Foreground service, battery-opt exemption prompt, crash-safe DB writes, test on Xiaomi/Samsung. |
| Slow cold GPS fix without A-GPS | Waiting-for-fix state, onboarding tip to open before losing signal. |
| Forest canopy noise | Accuracy filter, spike rejection, smoothing, 30 m alert threshold. |
| Map file sizes | Max zoom 15, per-region files, optional download. |
| Compass inaccuracy near metal / uncalibrated | Fallback to GPS bearing when moving; calibration hint. |
| Safety liability | Disclaimer: aid, not a substitute for map, compass, telling someone your plan. |

## 18. Decisions

| Decision | Status |
|---|---|
| App name | ✅ Backtrack |
| Repo | ✅ Private, `Erik-Fazlla/backtrack` |
| Distribution | ✅ Personal use, direct install, no store |
| First map region | ✅ Greece |
| New regions | ✅ Stage 1 PC script + import (v0.2), Stage 2 in-app download (v0.3) |
| Map style | ✅ Light / dark selectable in settings; colours customizable |
| Tooling | ✅ Flutter + Android Studio |
| Default categories | ⏳ Proposed Run, Hike, Walk, Bike, Other |
| Follow saved journey: arrow to start or end by default | ⏳ Proposed: ask each time |
