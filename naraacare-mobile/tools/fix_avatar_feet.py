"""Cleans the bottom edge of an avatar asset (owner 2026-11-24: "the shoes are not cropped properly").

The cut-out of ``male_pick.webp`` (Profile.pdf jacket figure) left a straight 40 px stub of white
background under the left shoe that runs into the image's bottom edge, so the sole looks chopped
off. This script:
  1. finds where the sole really ends (rows below it are much narrower than the shoe: that is the
     stub) and clears every row below it;
  2. adds a transparent bottom margin, like the other avatars (12 px), so nothing touches the edge.

Usage (Pillow required), from naraacare-mobile:
  python -I tools/fix_avatar_feet.py assets/avatars/male_pick.webp
"""

import sys
from pathlib import Path

from PIL import Image

MARGIN = 12
STUB_ROWS = 6  # fewer narrow rows than this at the bottom = nothing to clean
STUB_SHARE = 0.6  # a row narrower than 60 % of the shoe is the stub, not the sole
LOOK_UP = 40  # rows above the bottom edge measured (only the lower, left shoe reaches them)


def opaque_count(alpha: Image.Image, y: int) -> int:
    return sum(1 for x in range(alpha.width) if alpha.getpixel((x, y)) > 10)


def sole_end(alpha: Image.Image) -> int:
    """Last row of the sole. The stub is much narrower than the shoe above it, so scanning up from
    the bottom, every row narrower than STUB_SHARE of the shoe's width belongs to the stub."""
    bottom = alpha.height - 1
    shoe = max(opaque_count(alpha, y) for y in range(bottom - LOOK_UP, bottom))
    y = bottom
    while y > bottom - LOOK_UP and opaque_count(alpha, y) < STUB_SHARE * shoe:
        y -= 1
    return y if bottom - y >= STUB_ROWS else bottom


def main(path: Path) -> None:
    im = Image.open(path).convert("RGBA")
    alpha = im.getchannel("A")
    end = sole_end(alpha)
    fixed = Image.new("RGBA", (im.width, end + 1 + MARGIN), (0, 0, 0, 0))
    fixed.paste(im.crop((0, 0, im.width, end + 1)), (0, 0))
    fixed.save(path, "WEBP", quality=88, method=6)
    print(path.name, im.size, "->", fixed.size, f"(cleared below row {end})")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
