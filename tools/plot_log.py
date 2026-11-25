"""Plot a real raw GPS log against the trail the app drew.

Usage:  python tools/plot_log.py test/real_logs/raw_XXXX.jsonl [more...]
Writes test/real_logs/out/<name>.png (git-ignored) and prints analysis:
  - start: how far the early fixes wander while the walk begins
  - lag: how far the drawn trail is behind the raw fix, by speed
"""
import json
import math
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

M = 111195.0


def load(path):
    meta, pts = {}, []
    for line in Path(path).read_text(encoding="utf8").splitlines():
        if not line.strip():
            continue
        try:
            j = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "meta" in j:
            meta = j["meta"]
        elif "pre" in j:
            continue  # warm-up fix before Record
        elif "end" not in j:
            pts.append(j)
    return meta, pts


def xy(pts, lat0, lon0):
    c = math.cos(math.radians(lat0))
    return ([(p["lon"] - lon0) * M * c for p in pts],
            [(p["lat"] - lat0) * M for p in pts])


def main():
    for raw_path in sys.argv[1:]:
        raw_path = Path(raw_path)
        name = raw_path.stem
        meta, raw = load(raw_path)
        _, trail = load(raw_path.with_name(raw_path.name.replace("raw_", "session_")))
        lat0, lon0 = raw[0]["lat"], raw[0]["lon"]
        rx, ry = xy(raw, lat0, lon0)
        tx, ty = xy(trail, lat0, lon0)

        fig, ax = plt.subplots(figsize=(8, 8))
        sc = ax.scatter(rx, ry, c=range(len(rx)), cmap="viridis", s=12,
                        label="raw GPS (colour = time)")
        ax.plot(tx, ty, "-", color="#FF6B00", lw=2.5, label="app trail")
        ax.plot(rx[0], ry[0], "o", color="green", ms=10, label="first raw fix")
        if tx:
            ax.plot(tx[0], ty[0], "s", color="red", ms=8, label="trail start")
        for i in range(0, len(raw), 10):
            ax.annotate(str(i), (rx[i], ry[i]), fontsize=7, color="gray")
        ax.set_aspect("equal")
        ax.grid(alpha=0.3)
        ax.set_title(f"{name}  gps={meta.get('gpsMode')}  (metres)")
        ax.legend(loc="best", fontsize=8)
        fig.colorbar(sc, ax=ax, label="seconds")
        out = Path("test/real_logs/out")
        out.mkdir(parents=True, exist_ok=True)
        fig.savefig(out / f"{name}.png", dpi=110, bbox_inches="tight")
        plt.close(fig)

        # --- analysis -------------------------------------------------
        print(f"== {name} ({meta.get('gpsMode')}) -> {out / (name + '.png')}")
        print(" first 20 s:  t  x     y     acc  spd")
        for i, p in enumerate(raw[:20]):
            print(f"            {i:2d} {rx[i]:5.1f} {ry[i]:5.1f} {p['acc']:4.1f} "
                  f"{p.get('spd', -1):4.2f}")
        spd = [p.get("spd") or 0 for p in raw]
        print(f" speed m/s: median {sorted(spd)[len(spd)//2]:.2f}  max {max(spd):.2f}")


if __name__ == "__main__":
    main()
