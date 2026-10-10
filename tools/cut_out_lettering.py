"""Cut lettering out of a white background (used for assets/images/logo_pentafall.png and title_defeat.png).

usage: python -I tools/cut_out_lettering.py <in.jpg> <out.png> [min_hole_px] [white_threshold]

Background = near-white regions connected to the border, plus enclosed near-white regions
larger than min_hole_px (letter counters). Smaller enclosed near-white specks are kept as
metal highlights. Region growing runs at quarter resolution in numpy (no scipy here), then
is mapped back onto the full-resolution near-white pixels. Edges get alpha from their
distance to white inside a thin band around the background, and the white is divided back
out of their colour.
"""
import sys
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
min_hole = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
WHITE_T = int(sys.argv[4]) if len(sys.argv) > 4 else 232  # min channel above this is a background candidate
SOFT_LOW = 150     # in the edge band, min channel at or below this is fully opaque
F = 4              # working downscale for region growing


def grow(m, steps=1):
    """8-neighbour dilation of a bool mask."""
    for _ in range(steps):
        p = np.pad(m, 1)
        m = (p[:-2, :-2] | p[:-2, 1:-1] | p[:-2, 2:] | p[1:-1, :-2] | p[1:-1, 1:-1]
             | p[1:-1, 2:] | p[2:, :-2] | p[2:, 1:-1] | p[2:, 2:])
    return m


def shrink(m, steps=1):
    return ~grow(~m, steps)


def reconstruct(seed, mask):
    """Everything in `mask` connected to `seed`."""
    cur = seed & mask
    while True:
        nxt = grow(cur) & mask
        if nxt.sum() == cur.sum():
            return nxt
        cur = nxt


img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
h, w, _ = img.shape
mins = img.min(axis=2)
cand = mins > WHITE_T

# Quarter resolution: a block is background-ish when most of it is near white.
hh, ww = h // F, w // F
low = cand[:hh * F, :ww * F].reshape(hh, F, ww, F).mean(axis=(1, 3)) > 0.5
border = np.zeros_like(low)
border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
outside = reconstruct(border, low)
# Counters: what survives shrinking the rest is only the big regions; grow them back.
rest = low & ~outside
core = shrink(rest, max(1, int(np.sqrt(min_hole)) // (2 * F)))
holes = reconstruct(core, rest)
bg_low = outside | holes

bg = np.zeros((h, w), bool)
bg[:hh * F, :ww * F] = np.repeat(np.repeat(bg_low, F, axis=0), F, axis=1)
# The last partial row/column of blocks follows its neighbour.
bg[hh * F:, :] = bg[hh * F - 1:hh * F, :]
bg[:, ww * F:] = bg[:, ww * F - 1:ww * F]
# Only near-white pixels are background; a block's darker pixels are lettering edges.
bg = grow(bg, 1) & cand

alpha = np.where(bg, 0.0, 1.0).astype(np.float32)
band = grow(bg, 3) & ~bg
soft = np.clip((255.0 - mins) / (255.0 - SOFT_LOW), 0.0, 1.0)
alpha = np.where(band, soft, alpha)

a = alpha[..., None]
rgb = np.where(a > 0.01, (img - (1.0 - a) * 255.0) / np.maximum(a, 0.01), 0.0)
rgb = np.clip(rgb, 0, 255)

out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
ys, xs = np.nonzero(alpha > 0.02)
pad = int(0.02 * max(h, w))
y0, y1 = max(ys.min() - pad, 0), min(ys.max() + pad, h - 1)
x0, x1 = max(xs.min() - pad, 0), min(xs.max() + pad, w - 1)
Image.fromarray(out[y0:y1 + 1, x0:x1 + 1], "RGBA").save(dst)
print(dst, x1 - x0 + 1, "x", y1 - y0 + 1)
