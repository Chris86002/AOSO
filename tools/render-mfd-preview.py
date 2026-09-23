"""Render a sample MFD arrangement: python tools/render-mfd-preview.py OUT.png.

Requires Pillow. The preview is a layout reference, not a live kOS screenshot.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "AOSO/ux/ui2_assets"


def render(output):
    out = Image.new("RGB", (920, 650), "#0c1416")
    draw = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 16)
        small = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 13)
    except OSError:
        font = ImageFont.load_default()
        small = font
    green, pale, dim = "#1af034", "#b2ffd0", "#348f50"
    draw.rectangle((2, 2, 917, 647), outline="#506168", width=3)
    draw.text((22, 15), "AOSO  FLIGHT DECK / OPS DISPLAY r4", fill=green, font=font)
    draw.text((22, 42), "SYS NOMINAL     DOING: COAST TO TARGET", fill=pale, font=small)
    for i, title in enumerate(("PFD", "NAV", "TOUR", "VEH", "SURF", "SYS")):
        x = 20 + i * 145
        draw.rectangle((x, 78, x + 135, 107), outline=green if i == 0 else dim)
        draw.text((x + 45, 85), title, fill=green if i == 0 else pale, font=small)
    left = Image.open(ASSETS / "pfd_frame.png").convert("RGB")
    right = Image.open(ASSETS / "readout_frame.png").convert("RGB")
    out.paste(left, (23, 167))
    out.paste(right, (467, 135))
    draw.text((45, 130), "PRIMARY FLIGHT DISPLAY", fill=green, font=font)
    draw.text((53, 420), "PITCH +12.0  ROLL -8.0  AoA +3.0", fill=pale, font=small)
    draw.text((53, 445), "TWR 1.36   THR 64%   STAGE 2", fill=pale, font=small)
    draw.text((490, 152), "FLIGHT / LIVE TELEMETRY", fill=green, font=small)
    lines = [
        "BODY       KERBIN / ORBIT", "ALT        82.3 km  VS +12 m/s",
        "SPEED      ORB 2,304 m/s", "ATTITUDE   HDG 090  P +12  R -8",
        "ORBIT      AP 84 km  PE 80 km", "TWR        1.36  THR 64%",
        "GUIDANCE   COAST", "STEERING   PROGRADE", "NAVIGATION TARGET: MUN",
        "PRIORITY   NOMINAL",
    ]
    for i, line in enumerate(lines):
        draw.text((487, 192 + i * 28), line, fill=pale, font=small)
    draw.text((21, 610), "PFD   NAV   TOUR   VEH   SURF   SYS   /   PROP   STAGE   TWIN   LOG   DBG   HELP", fill=dim, font=small)
    output.parent.mkdir(parents=True, exist_ok=True)
    out.save(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    render(parser.parse_args().output)
