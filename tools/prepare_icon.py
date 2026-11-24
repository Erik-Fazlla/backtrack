"""Turn a square artwork (black background) into Backtrack's icon files.

Usage: python tools/prepare_icon.py <source image>
Writes:
  assets/icon/source.png   original, kept for re-runs
  assets/icon/icon.png     1024 full icon (legacy launchers)
  assets/icon/icon_fg.png  adaptive foreground: art scaled into the centre
                           safe zone (Android crops to circle/squircle)
  assets/icon/icon_mono.png themed-icon mask: brightness -> alpha
Then: dart run flutter_launcher_icons
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path("assets/icon")
OUT.mkdir(parents=True, exist_ok=True)

src = Image.open(sys.argv[1]).convert("RGB")
w, h = src.size
side = min(w, h)
src = src.crop(((w - side) // 2, (h - side) // 2,
                (w + side) // 2, (h + side) // 2)).resize((1024, 1024), Image.LANCZOS)
src.save(OUT / "source.png")
src.save(OUT / "icon.png")

# Adaptive foreground: shrink art to ~68 % so the glow survives the crop.
fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
small = src.resize((696, 696), Image.LANCZOS).convert("RGBA")
fg.paste(small, ((1024 - 696) // 2, (1024 - 696) // 2))
fg.save(OUT / "icon_fg.png")

# Monochrome (Android 13 themed icons): shape from brightness.
lum = np.asarray(small.convert("L"), dtype=np.float32)
alpha = np.clip((lum - 25) * 2.2, 0, 255).astype(np.uint8)
mono_small = Image.new("RGBA", small.size, (255, 255, 255, 0))
mono_small.putalpha(Image.fromarray(alpha))
mono = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
mono.paste(mono_small, ((1024 - 696) // 2, (1024 - 696) // 2))
mono.save(OUT / "icon_mono.png")
print("wrote", *(OUT / n for n in ("icon.png", "icon_fg.png", "icon_mono.png")))
