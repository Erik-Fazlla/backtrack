"""Generate a walking-speed GPX route for testing Backtrack without walking.

Used two ways:
  1. Replay test on PC (test/replay_test.dart) feeds it through the recorder.
  2. Android emulator: Extended controls -> Location -> Routes -> Import GPX
     -> Play route. The app then records it like a real walk.

Usage:  python tools/make_route.py > test/fixtures/block_loop.gpx
"""
import math
from datetime import datetime, timedelta, timezone

# Rectangle loop with sharp 90-degree corners around a city block
# (Syntagma, Athens). Corners as (north metres, east metres) from start.
START = (37.97550, 23.73480)
CORNERS_M = [(0, 0), (120, 0), (120, -150), (0, -150), (0, 0)]
SPEED_MPS = 1.4  # normal walking
STEP_S = 1       # one fix per second, like the real phone settings

M_PER_DEG_LAT = 111195.0


def to_latlon(n, e):
    lat = START[0] + n / M_PER_DEG_LAT
    lon = START[1] + e / (M_PER_DEG_LAT * math.cos(math.radians(START[0])))
    return lat, lon


def main():
    t = datetime(2026, 11, 22, 10, 0, 0, tzinfo=timezone.utc)
    pts = []
    for (n1, e1), (n2, e2) in zip(CORNERS_M, CORNERS_M[1:]):
        seg = math.hypot(n2 - n1, e2 - e1)
        steps = max(1, int(seg / (SPEED_MPS * STEP_S)))
        for i in range(steps):
            f = i / steps
            pts.append((to_latlon(n1 + (n2 - n1) * f, e1 + (e2 - e1) * f), t))
            t += timedelta(seconds=STEP_S)
    pts.append((to_latlon(*CORNERS_M[-1]), t))

    print('<?xml version="1.0" encoding="UTF-8"?>')
    print('<gpx version="1.1" creator="backtrack-tools" '
          'xmlns="http://www.topografix.com/GPX/1/1">')
    print('  <trk><name>Block loop (540 m, sharp corners)</name><trkseg>')
    for (lat, lon), ts in pts:
        print(f'    <trkpt lat="{lat:.7f}" lon="{lon:.7f}">'
              f'<ele>80</ele><time>{ts.strftime("%Y-%m-%dT%H:%M:%SZ")}</time>'
              f'</trkpt>')
    print('  </trkseg></trk>')
    print('</gpx>')


if __name__ == '__main__':
    main()
