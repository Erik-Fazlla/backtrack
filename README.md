# Backtrack

Offline trail recorder for Android. Record where you walk with no signal and
no internet, see it on an offline map, and follow it back to the start.
Save journeys to reuse later.

Everything stays on your phone: no account, no cloud, no tracking.

## Features

- **Record** your trail from GPS alone (works with no signal or mobile data).
  A GPS indicator turns green when the position is accurate enough to start.
- **Take me back / Follow** a trail: an arrow shows which way to turn, the
  distance left counts down, and the phone vibrates if you leave the trail.
- **Offline maps** (Protomaps `.pmtiles`), light or dark style, rotatable map,
  compass and a direction beam on your position. Full-screen map mode.
- **Library** of saved journeys with search, sorting and categories
  (Run, Hike, Walk, Bike, Other, plus your own with custom colours).
- **Map** of all saved journeys; tap a line for its stats.
- **Elevation**: uphill / downhill totals and an elevation profile.
- Optional snap-to-path display.

## Install

1. On your Android phone, download the `.apk` from the
   [latest release](../../releases/latest).
2. Open it and allow "install unknown apps" for your browser or file app.
3. Allow location and notifications. Recording keeps running with the screen
   off (shown as a notification).

Android 7.0 or newer. Not on the Play Store.

## Offline maps

The app does not include map data. Cut a region from the free Protomaps
planet build with [`tools/cut_region.ps1`](tools/cut_region.ps1) (uses the
official `pmtiles` CLI), copy the `.pmtiles` file to the phone, then in
Backtrack open Settings (gear) -> Offline maps -> Import map file. Without a
map the trail still records and shows on a plain background.

## Build from source

```
flutter pub get
flutter test
flutter build apk --release
```

Flutter 3.44 / Dart 3.12. See [docs/SPEC.md](docs/SPEC.md) for the design and
[docs/TESTING-ON-PC.md](docs/TESTING-ON-PC.md) for testing with recorded GPS logs.

## Credits

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, tiles by [Protomaps](https://protomaps.com).

## License

[MIT](LICENSE)
