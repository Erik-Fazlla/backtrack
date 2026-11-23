"""Plot raw vs snapped trail over the map's path lines.

Usage: flutter test test/path_snap_real_test.dart  (writes the JSON)
       python tools/plot_snap.py
Output: test/real_logs/out/street_snap.png (git-ignored)
"""
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

d = json.loads(Path("test/real_logs/out/street_snap.json").read_text())
lat0, lon0 = d["raw"][0]
c = math.cos(math.radians(lat0))


def xy(pts):
    return ([(p[1] - lon0) * 111195 * c for p in pts],
            [(p[0] - lat0) * 111195 for p in pts])


fig, ax = plt.subplots(figsize=(9, 11))
for line in d["lines"]:
    x, y = xy(line)
    ax.plot(x, y, color="#bbbbbb", lw=1.2)
x, y = xy(d["raw"])
ax.plot(x, y, color="#FF6B00", lw=2, label="recorded trail")
x, y = xy(d["snapped"])
ax.plot(x, y, color="#1E6FE8", lw=2, label="snapped to paths")
rx, ry = xy(d["raw"])
ax.set_xlim(min(rx) - 40, max(rx) + 40)
ax.set_ylim(min(ry) - 40, max(ry) + 40)
ax.set_aspect("equal")
ax.legend()
ax.set_title("Street walk: recorded vs snapped (metres; grey = map paths)")
out = Path("test/real_logs/out/street_snap.png")
fig.savefig(out, dpi=100, bbox_inches="tight")
print(out)
