#!/usr/bin/env python3
"""
Converts the near-white background the model actually produces (despite being
asked for transparency) into true alpha transparency.

The naive approach (flood-fill straight from the border) leaves speckled
noise behind: the "white" background isn't perfectly flat at the pixel level
(mild dithering/compression artifacts), so a plain flood fill misses many
small islands that are technically a few units off-white.

This instead: (1) builds a whiteness mask from the per-pixel minimum channel
value (background/white-on-white is high on all channels; colorful subject
pixels always have at least one low channel), (2) cleans that mask with a
morphological opening (drops tiny noise specks) then closing (fills tiny gaps
in the background), (3) flood-fills ONLY the border-connected component of
the cleaned mask to transparent -- so isolated white regions fully enclosed
by the subject's own outline (eye whites, etc.) are correctly left opaque.

Usage: python3 knockout_bg.py <input.png> <output.png> [white_thresh]
"""
import sys
from PIL import Image, ImageChops, ImageFilter, ImageDraw

def whiteness_mask(img):
    r, g, b = img.split()[:3]
    return ImageChops.darker(ImageChops.darker(r, g), b)  # min(r,g,b) per pixel

def knockout(in_path, out_path, white_thresh=175, open_size=3, close_size=5):
    img = Image.open(in_path).convert("RGBA")
    w, h = img.size

    mask = whiteness_mask(img).point(lambda p: 255 if p > white_thresh else 0)
    # Opening: drop small noise specks (smaller than open_size) without
    # touching legitimate larger shapes (sparkles, eye whites, ...).
    mask = mask.filter(ImageFilter.MinFilter(open_size)).filter(ImageFilter.MaxFilter(open_size))
    # Closing: fill tiny gaps/dither holes inside the real background blob.
    mask = mask.filter(ImageFilter.MaxFilter(close_size)).filter(ImageFilter.MinFilter(close_size))

    # Flood-fill only the border-connected white region -> that's the true
    # background; anything white but NOT reachable from the border (enclosed
    # by the subject's own outline) stays opaque.
    ff = mask.convert("L").copy()
    seeds = {(x, 0) for x in range(w)} | {(x, h - 1) for x in range(w)} \
          | {(0, y) for y in range(h)} | {(w - 1, y) for y in range(h)}
    for sx, sy in seeds:
        if ff.getpixel((sx, sy)) == 255:
            ImageDraw.floodfill(ff, (sx, sy), 128, thresh=0)
    final_mask = ff.point(lambda p: 0 if p == 128 else 255)  # 0 = transparent

    px = img.load()
    fm = final_mask.load()
    for y in range(h):
        for x in range(w):
            if fm[x, y] == 0:
                r, g, b, a = px[x, y]
                px[x, y] = (r, g, b, 0)
    img.save(out_path)

    transparent = sum(1 for y in range(h) for x in range(w) if px[x, y][3] == 0)
    print(f"[knockout] {in_path} -> {out_path}: {transparent}/{w*h} px transparent "
          f"({100*transparent/(w*h):.1f}%), white_thresh={white_thresh}")

if __name__ == "__main__":
    in_path, out_path = sys.argv[1], sys.argv[2]
    white_thresh = int(sys.argv[3]) if len(sys.argv) > 3 else 175
    knockout(in_path, out_path, white_thresh)
