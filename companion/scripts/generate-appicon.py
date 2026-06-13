#!/usr/bin/env python3
"""Generate companion/Resources/AppIcon.icns from icon-source.png.

Hybrid app icon: large sizes keep the full branded art (branch graph + the
"WorkBranch Companion" wordmark); small sizes (<= 64 px) drop the wordmark and
use a centered, text-free branch graph so the icon stays legible in Finder list
views and small Gatekeeper/menu surfaces (Apple HIG advises against text in
app icons because it smudges at small sizes).

This script is a maintainer tool, NOT part of the CI build. The build
(`scripts/build-app.sh`) only copies the pre-generated `AppIcon.icns`, so the
release pipeline stays dependency-free. Regenerate after changing the source:

    python3 -m venv /tmp/iconvenv && /tmp/iconvenv/bin/pip install Pillow
    /tmp/iconvenv/bin/python companion/scripts/generate-appicon.py

Requires: Pillow, and macOS `iconutil` (for the final .icns assembly).
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
RES = HERE.parent / "Resources"
SRC = RES / "icon-source.png"
OUT = RES / "AppIcon.icns"

BG = (38, 41, 47)  # dark squircle interior, sampled from the source art


def brightness(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def saturation(p):
    return max(p[0], p[1], p[2]) - min(p[0], p[1], p[2])


def is_exterior(p):
    # White canvas around the squircle, or transparent padding.
    return p[3] < 10 or (p[0] > 200 and p[1] > 200 and p[2] > 200)


def make_text_free(src: Image.Image) -> Image.Image:
    """Rebuild the icon as a clean dark squircle with a centered branch graph."""
    W, H = src.size
    px = src.load()

    # Per-row horizontal extent of the squircle silhouette (exact, preserves
    # the rounded corners against the white canvas).
    rows = {}
    sq_top = sq_bot = None
    for y in range(H):
        xs = [x for x in range(W) if not is_exterior(px[x, y])]
        if xs:
            rows[y] = (xs[0], xs[-1])
            if sq_top is None:
                sq_top = y
            sq_bot = y

    # Flat-fill the squircle interior with the background, erasing graph + text.
    clean = src.copy()
    cp = clean.load()
    for y, (l, r) in rows.items():
        for x in range(l, r + 1):
            cp[x, y] = (BG[0], BG[1], BG[2], 255)

    # Find the branch-graph bounding box: strongly colored or bright-white
    # pixels, inset from the squircle edge (skips anti-aliased rim) and above
    # the wordmark band.
    inset = 60
    y_limit = int(0.62 * H)
    minx = miny = 10 ** 9
    maxx = maxy = -1
    for y in range(sq_top + inset, y_limit):
        l, r = rows.get(y, (0, -1))
        if r - l < 2 * inset:
            continue
        for x in range(l + inset, r - inset + 1):
            p = px[x, y]
            if saturation(p) > 60 or brightness(p) > 175:
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
    if maxx < 0:
        raise SystemExit("could not locate branch graph in source art")

    pad = 40
    box = (max(0, minx - pad), max(0, miny - pad),
           min(W, maxx + pad), min(H, maxy + pad))
    graph = src.crop(box).copy()
    gw, gh = graph.size

    # Mask the graph by color distance from the background so only the graph
    # (not its rectangular crop background) composites — avoids a visible seam.
    gp = graph.load()
    for y in range(gh):
        for x in range(gw):
            p = gp[x, y]
            d = abs(p[0] - BG[0]) + abs(p[1] - BG[1]) + abs(p[2] - BG[2])
            a = max(0, min(255, int((d - 18) * 255 / 45)))
            gp[x, y] = (p[0], p[1], p[2], a)

    sq_cy = (sq_top + sq_bot) // 2
    clean.alpha_composite(graph, ((W - gw) // 2, sq_cy - gh // 2))
    return clean


def main():
    if not SRC.exists():
        raise SystemExit(f"missing source art: {SRC}")
    src = Image.open(SRC).convert("RGBA")
    text_free = make_text_free(src)

    # (iconset filename, pixel size, use_text_free)
    spec = [
        ("icon_16x16.png", 16, True),
        ("icon_16x16@2x.png", 32, True),
        ("icon_32x32.png", 32, True),
        ("icon_32x32@2x.png", 64, True),
        ("icon_128x128.png", 128, False),
        ("icon_128x128@2x.png", 256, False),
        ("icon_256x256.png", 256, False),
        ("icon_256x256@2x.png", 512, False),
        ("icon_512x512.png", 512, False),
        ("icon_512x512@2x.png", 1024, False),
    ]

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for name, size, text_free_variant in spec:
            base = text_free if text_free_variant else src
            img = base.resize((size, size), Image.LANCZOS)
            img.save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)],
            check=True,
        )
    print(f"[+] wrote {OUT}")


if __name__ == "__main__":
    sys.exit(main())
