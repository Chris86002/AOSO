"""Render a layout sample without KSP: python tools/render-hud-preview.py OUT.png.

Requires Pillow. This checks asset geometry and label placement; Unity's kOS
GUI remains the final rendering authority. Use the in-game TEST control for it.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "AOSO/ux/ui2_assets"


def render(output):
    glass = Image.open(ASSETS / "hud_overlay.png").convert("RGBA")
    if glass.size != (360, 240):
        raise ValueError(f"HUD glass is {glass.size}, expected 360x240")
    out = Image.new("RGBA", (580, 390), (3, 8, 9, 185))
    draw = ImageDraw.Draw(out)
    green, dim, white = "#1af034", "#348f50", "#b2ffd0"
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 16)
        small = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 12)
    except OSError:
        font = ImageFont.load_default()
        small = font
    draw.rectangle((3, 3, 576, 386), outline=dim, width=2)
    draw.text((12, 10), "AOSO / GEOM TEST", fill=green, font=font)
    draw.text((195, 13), "HDG 090", fill=white, font=small)
    x = 270
    for label, width in (("DCL", 42), ("REC", 42), ("CTR", 43), ("DUMP", 50), ("MFD", 42)):
        draw.rectangle((x, 7, x + width - 3, 32), outline=dim)
        draw.text((x + 5, 13), label, fill=white, font=small)
        x += width
    draw.text((135, 40), "PITCH +12.0    ROLL -08.0    AoA +03.0", fill=white, font=small)
    out.alpha_composite(glass, (90, 70))
    draw.text((9, 80), "SPEED m/s", fill=dim, font=small)
    draw.text((24, 107), "250", fill=white, font=font)
    draw.text((20, 134), "VS +75", fill=green, font=small)
    draw.text((453, 80), "ALTITUDE", fill=dim, font=small)
    draw.text((460, 107), "10.0km", fill=white, font=font)
    draw.text((460, 134), "AP 80km", fill=green, font=small)
    draw.rectangle((545, 75, 552, 298), outline=dim)
    draw.rectangle((541, 160, 556, 169), fill=green)
    draw.rectangle((90 + 180 - 7, 70 + 120 - 7, 90 + 180 + 7, 70 + 120 + 7), outline=green, width=2)
    draw.text((140, 317), "TEST ONLY - NO FLIGHT COMMANDS", fill=green, font=small)
    draw.text((12, 341), "dV / PROP", fill=dim, font=small)
    draw.rectangle((100, 343, 430, 355), outline=dim)
    draw.rectangle((101, 344, 265, 354), fill=green)
    draw.text((442, 341), "50% TEST", fill=white, font=small)
    draw.text((80, 370), "ART 360x240  BUG 180,120  DATA AGE 0.1s", fill=dim, font=small)
    output.parent.mkdir(parents=True, exist_ok=True)
    out.convert("RGB").save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    render(parser.parse_args().output)
