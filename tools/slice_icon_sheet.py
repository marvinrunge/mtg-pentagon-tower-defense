"""Cut a generated sheet of skill icons into the separate files the game loads.

The sheet is what the one-image prompt in docs/ICON_PROMPTS.md asks for: a 3 x 3 grid of
square icons, in the order listed in NAMES below (row by row). Image generators never lay a
grid out exactly, so the cuts are not taken at thirds blindly: each one is moved to the
plainest line (the gutter) within a band around the third, and every cell is then trimmed
to its icon and squared.

Usage:
    python tools/slice_icon_sheet.py <sheet.png> [out_dir] [--size 256] [--force]

out_dir defaults to assets/icons. Existing files are left alone unless --force is given.
Needs Pillow (pip install pillow).
"""

import argparse
import os
import sys

from PIL import Image, ImageChops, ImageStat

# Row by row, as the prompt numbers them.
NAMES = [
    "wall-of-frost", "contagion", "kodamas-reach",
    "guild-azorius", "guild-dimir", "guild-rakdos",
    "guild-gruul", "guild-selesnya", "displace",
]
GRID = 3
# How far either side of a third the gutter is looked for, as a share of the sheet.
SEARCH = 0.06


def _line_score(image: Image.Image, position: int, vertical: bool) -> float:
    """How busy one row or column is - a gutter is plain, so it scores low."""
    width, height = image.size
    box = (position, 0, position + 1, height) if vertical else (0, position, width, position + 1)
    stat = ImageStat.Stat(image.crop(box))
    return sum(stat.stddev)


def _cuts(image: Image.Image, vertical: bool) -> list[int]:
    length = image.size[0] if vertical else image.size[1]
    grey = image.convert("L")
    cuts = [0]
    for k in range(1, GRID):
        guess = int(length * k / GRID)
        reach = int(length * SEARCH)
        lo, hi = max(1, guess - reach), min(length - 2, guess + reach)
        cuts.append(min(range(lo, hi + 1), key=lambda p: _line_score(grey, p, vertical)))
    cuts.append(length)
    return cuts


def _trim(cell: Image.Image) -> Image.Image:
    """Crops a cell to its icon: everything that differs from the gutter colour in its corners."""
    rgb = cell.convert("RGB")
    corners = [rgb.getpixel(p) for p in [(0, 0), (rgb.width - 1, 0), (0, rgb.height - 1),
                                         (rgb.width - 1, rgb.height - 1)]]
    gutter = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
    diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, gutter)).convert("L")
    box = diff.point(lambda v: 255 if v > 28 else 0).getbbox()
    if box is None:
        box = (0, 0, rgb.width, rgb.height)
    # Square, centred on the icon, never past the cell.
    left, top, right, bottom = box
    side = max(right - left, bottom - top)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    side = min(side, cell.width, cell.height)
    left = min(max(0, cx - side // 2), cell.width - side)
    top = min(max(0, cy - side // 2), cell.height - side)
    return cell.crop((left, top, left + side, top + side))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("sheet")
    parser.add_argument("out_dir", nargs="?", default=os.path.join("assets", "icons"))
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    sheet = Image.open(args.sheet).convert("RGBA")
    xs, ys = _cuts(sheet, True), _cuts(sheet, False)
    os.makedirs(args.out_dir, exist_ok=True)
    for row in range(GRID):
        for column in range(GRID):
            name = NAMES[row * GRID + column]
            path = os.path.join(args.out_dir, name + ".png")
            if os.path.exists(path) and not args.force:
                print(f"skip  {path} (exists; --force to overwrite)")
                continue
            cell = sheet.crop((xs[column], ys[row], xs[column + 1], ys[row + 1]))
            icon = _trim(cell).resize((args.size, args.size), Image.LANCZOS)
            icon.save(path)
            print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
