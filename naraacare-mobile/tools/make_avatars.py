"""Builds the app's avatar assets from the Figma exports in D:\\Figma images.

Sources (extracted at full resolution from the Figma PDFs / PNG exports):
  * Home/Water.pdf image 1448x1086: male + female in light-blue (water state) outfits
  * Profile.pdf image 904x1739 + its alpha mask: male in jacket (onboarding sex picker)
  * image 69.png 533x1086: female in teal shirt (onboarding sex picker)
State variants keep skin and hair untouched and recolour only the outfit (bluish pixels):
water = Figma blue, food = mint (Figma "Home/Nutrition"), neutral = white (Figma "After sign in").

Usage (Pillow required):
  python -I tools/pdf_images.py <tmp_dir> "D:/Figma images/Home/Water.pdf" "D:/Figma images/Profile.pdf"
  python -I tools/make_avatars.py <tmp_dir>
"""

import colorsys
import sys
from pathlib import Path

from PIL import Image

PDF_OUT = Path(sys.argv[1])
FIGMA = Path(r"D:\Figma images")
OUT = Path(r"D:\Naara Care\naraacare-mobile\assets\avatars")
OUT.mkdir(parents=True, exist_ok=True)


def trim(im: Image.Image, margin: int = 12) -> Image.Image:
    """Crop to the figure: pixels clearly darker than the white background."""
    gray = im.convert("L").point(lambda v: 255 if v < 238 else 0)
    l, t, r, b = gray.getbbox()
    return im.crop((max(0, l - margin), max(0, t - margin), min(im.width, r + margin), min(im.height, b + margin)))


def recolour(im: Image.Image, hue: float | None, sat_scale: float) -> Image.Image:
    """Shift outfit pixels (hue 180-260 deg, some saturation) to `hue`, or desaturate when None."""
    rgb = im.convert("RGB")
    px = rgb.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            r, g, b = px[x, y]
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if 0.5 <= h <= 0.72 and s > 0.08 and l > 0.35:
                nh = h if hue is None else hue
                nr, ng, nb = colorsys.hls_to_rgb(nh, l, s * sat_scale)
                px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255))
    return rgb


def save(im: Image.Image, name: str) -> None:
    im.save(OUT / f"{name}.webp", "WEBP", quality=88, method=6)
    print(name, im.size, (OUT / f"{name}.webp").stat().st_size // 1024, "KB")


pair = Image.open(PDF_OUT / "Water_obj66_1448x1086.jpg").convert("RGB")
half = pair.width // 2
figures = {"male": trim(pair.crop((0, 0, half, pair.height))), "female": trim(pair.crop((half, 0, pair.width, pair.height)))}
for sex, fig in figures.items():
    save(fig, f"{sex}_water")
    save(recolour(fig, hue=135 / 360, sat_scale=0.75), f"{sex}_food")
    save(recolour(fig, hue=None, sat_scale=0.0), f"{sex}_neutral")

male = Image.open(PDF_OUT / "Profile_obj186_904x1739.jpg").convert("RGB")
mask = Image.open(PDF_OUT / "Profile_obj184_904x1739.png").convert("L")
white = Image.new("RGB", male.size, (255, 255, 255))
save(trim(Image.composite(male, white, mask)), "male_pick")
save(trim(Image.open(FIGMA / "image 69.png").convert("RGB")), "female_pick")
