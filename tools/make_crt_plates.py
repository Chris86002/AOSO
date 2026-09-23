#!/usr/bin/env python3
"""Pixel-aligned AOSO CRT plates. Plot rectangle must match ui2_plots.ks."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = "/tmp/AOSO/AOSO/ux/ui2_assets"
W, H = 740, 400
OX, OY, PW, PH = 36, 52, 460, 280
FONT = "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf"
GREEN = (118, 255, 150, 255)
DIM = (36, 110, 64, 255)
AMBER = (255, 176, 46, 255)
YELLOW = (255, 214, 70, 255)
BLACK = (3, 6, 4, 255)

def font(size):
    return ImageFont.truetype(FONT, size)

def glow_text(base, xy, text, fill, size, anchor="lt"):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=font(size), fill=fill, anchor=anchor)
    blurred = layer.filter(ImageFilter.GaussianBlur(1.2))
    base.alpha_composite(blurred)
    base.alpha_composite(layer)

def scanlines(im):
    pix = im.load()
    for y in range(0, im.height, 3):
        for x in range(im.width):
            r, g, b, a = pix[x, y]
            pix[x, y] = (int(r * 0.72), int(g * 0.78), int(b * 0.72), a)

def bezel(d):
    d.rectangle((0, 0, W - 1, H - 1), outline=GREEN)
    d.rectangle((4, 4, W - 5, H - 5), outline=DIM)
    d.rectangle((8, 8, W - 9, H - 9), outline=GREEN)

def grid(d):
    d.rectangle((OX, OY, OX + PW, OY + PH), outline=GREEN)
    for i in range(1, 4):
        x = OX + int(PW * i / 4)
        y = OY + int(PH * i / 4)
        d.line((x, OY, x, OY + PH), fill=DIM)
        d.line((OX, y, OX + PW, y), fill=DIM)
    d.line((OX, OY + PH - 6, OX, OY + PH + 6), fill=GREEN)

def side_boxes(d, titles):
    x0, x1 = 516, 724
    top = 52
    row_h = 52
    for i, title in enumerate(titles):
        y0 = top + i * row_h
        y1 = y0 + row_h - 6
        d.rectangle((x0, y0, x1, y1), outline=DIM)
        d.text((x0 + 8, y0 + 4), title, font=font(12), fill=DIM)

def plate(name, title, subtitle, axis_x, axis_y, sides, extra=None):
    im = Image.new("RGBA", (W, H), BLACK)
    d = ImageDraw.Draw(im)
    bezel(d)
    glow_text(im, (18, 14), title, GREEN, 20)
    d = ImageDraw.Draw(im)
    d.text((250, 18), subtitle, font=font(13), fill=AMBER)
    grid(d)
    d.text((OX, OY + PH + 6), axis_x, font=font(12), fill=GREEN)
    if axis_y:
        d.text((OX + PW - 70, OY - 16), axis_y, font=font(12), fill=GREEN)
    side_boxes(d, sides)
    if extra:
        extra(d, im)
    scanlines(im)
    im.save(f"{OUT}/{name}")
    print(name, OX, OY, PW, PH)

def asc_extra(d, im):
    d.text((OX + 8, OY + 8), "0", font=font(11), fill=DIM)
    d.text((OX + 8, OY + PH - 16), "PAD", font=font(11), fill=DIM)

def vs_extra(d, im):
    d.line((OX + PW, OY, OX + PW, OY + PH), fill=AMBER)
    d.text((OX + PW - 36, OY + PH + 6), "SITE", font=font(12), fill=AMBER)

def rte_extra(d, im):
    d.rectangle((OX + 8, OY + 18, OX + PW - 8, OY + 92), outline=DIM)
    d.text((OX + 12, OY + 4), "ROUTE RIBBON", font=font(12), fill=DIM)
    d.rectangle((OX + 8, OY + 110, OX + PW - 8, OY + PH - 12), outline=DIM)
    d.text((OX + 12, OY + 116), "WINDOW", font=font(12), fill=DIM)

def bdg_extra(d, im):
    d.text((OX + 8, OY + 6), "LEFTOVER MISSION dV", font=font(12), fill=DIM)

plate("crt_asc.png", "ASC TRAJ", "ALTITUDE  /  DOWNRANGE", "DOWNRANGE km", "ALT km",
      ["Q", "AOA", "TWR", "PITCH", "STAGE", "LF VS BEST"], asc_extra)
plate("crt_vs.png", "VSIT", "ALTITUDE  /  RANGE TO SITE", "RANGE km   0 AT SITE", "ALT km",
      ["HDOT", "TWR", "MARGIN", "SITE", "RADAR", "LAND dV"], vs_extra)
plate("crt_rte.png", "ROUTE", "FEASIBILITY  /  WINDOW", "BODIES", "",
      ["HOP", "WINDOW", "CLASS", "END dV", "RETURN", "ABORT"], rte_extra)
plate("crt_bdg.png", "BUDGET", "PROJECTED STATE", "NOW  ->  EACH HOP", "",
      ["NOW", "UNUSABLE", "RESERVE", "LAND", "RETURN", "ABORT"], bdg_extra)
plate("crt_rnd.png", "RNDZ", "RANGE  /  CLOSING", "CLOSING", "LATERAL",
      ["TARGET", "RANGE", "RATE", "BEARING", "PORT", "REL"], None)

bw, bh = 360, 240
bore = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
bd = ImageDraw.Draw(bore)
bd.rectangle((0, 0, bw - 1, bh - 1), outline=GREEN)
cx, cy = bw // 2, bh // 2
for dy, label in ((-70, "20"), (-35, "10"), (35, "10"), (70, "20")):
    y = cy + dy
    bd.line((40, y, bw - 40, y), fill=DIM)
    bd.text((18, y - 6), label, font=font(11), fill=DIM)
bd.line((cx, 16, cx, bh - 16), fill=(40, 90, 55, 180))
bd.ellipse((cx - 18, cy - 18, cx + 18, cy + 18), outline=GREEN)
scanlines(bore)
bore.save(f"{OUT}/hud_overlay.png")

def triangle(size, fill, point="up"):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if point == "up":
        d.polygon([(size // 2, 1), (1, size - 2), (size - 2, size - 2)], fill=fill)
    else:
        d.polygon([(1, 1), (size - 2, 1), (size // 2, size - 2)], fill=fill)
    return im

triangle(18, YELLOW).save(f"{OUT}/ship_bug.png")
triangle(12, AMBER).save(f"{OUT}/trail_bug.png")
pred = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
ImageDraw.Draw(pred).ellipse((1, 1, 8, 8), outline=GREEN)
pred.save(f"{OUT}/pred_bug.png")
dia = Image.new("RGBA", (22, 22), (0, 0, 0, 0))
ImageDraw.Draw(dia).polygon([(11, 1), (21, 11), (11, 21), (1, 11)], outline=YELLOW)
dia.save(f"{OUT}/diamond.png")

def plain_key(name, fill):
    im = Image.new("RGBA", (88, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 87, 27), fill=(6, 16, 8, 255), outline=fill)
    d.rectangle((2, 2, 85, 25), outline=fill)
    im.save(f"{OUT}/{name}")

plain_key("button_off.png", DIM)
plain_key("button_hover.png", GREEN)
plain_key("button_on.png", AMBER)
plain_key("button_stby.png", DIM)
plain_key("button_warn.png", AMBER)
plain_key("button_fail.png", (255, 80, 70, 255))

# Bore origin (190, 62) is also hardcoded in aoso_ui2_hud_pipper_at.
gw, gh = 740, 400
glass = Image.new("RGBA", (gw, gh), BLACK)
gd = ImageDraw.Draw(glass)
gd.rectangle((0, 0, gw - 1, gh - 1), outline=GREEN)
gd.rectangle((4, 4, gw - 5, gh - 5), outline=DIM)
gd.rectangle((8, 8, gw - 9, gh - 9), outline=GREEN)
glow_text(glass, (18, 14), "GLASS", GREEN, 20)
gd = ImageDraw.Draw(glass)
gd.text((200, 16), "FLIGHT DIRECTOR", font=font(13), fill=AMBER)
gd.rectangle((18, 62, 176, 312), outline=DIM)
gd.text((26, 68), "SPEED", font=font(12), fill=DIM)
gd.rectangle((564, 62, 722, 312), outline=DIM)
gd.text((572, 68), "ALT", font=font(12), fill=DIM)
glass.alpha_composite(bore, (190, 62))
for title, x in (("VS", 18), ("AUTH", 180), ("GUID", 340), ("NOTE", 520)):
    gd.rectangle((x, 324, x + 150, 384), outline=DIM)
    gd.text((x + 8, 328), title, font=font(12), fill=DIM)
for word, x in (("ASC", 210), ("ORB", 268), ("XFR", 326), ("RNDZ", 390), ("DSC", 468), ("LND", 536)):
    gd.text((x, 40), word, font=font(12), fill=DIM)
scanlines(glass)
glass.save(f"{OUT}/crt_glass.png")

def save_key(slug, word, suffix, outline, text_fill):
    im = Image.new("RGBA", (88, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 87, 27), fill=(6, 16, 8, 255), outline=outline)
    d.rectangle((2, 2, 85, 25), outline=outline)
    d.text((44, 14), word, font=font(12), fill=text_fill, anchor="mm")
    im.save(f"{OUT}/key_{slug}_{suffix}.png")

for slug, word in (
    ("asc", "ASC"), ("vsit", "VSIT"), ("route", "ROUTE"), ("dv", "DV"),
    ("rndz", "RNDZ"), ("hud", "HUD"), ("fd", "FD"), ("auto", "AUTO"),
    ("dcl", "DCL"), ("rec", "REC"), ("test", "TEST"), ("dump", "DUMP"),
    ("mfd", "MFD"),
):
    save_key(slug, word, "off", DIM, DIM)
    save_key(slug, word, "hot", GREEN, GREEN)
    save_key(slug, word, "on", AMBER, AMBER)

mark = Image.new("RGBA", (18, 4), (0, 0, 0, 0))
ImageDraw.Draw(mark).rectangle((0, 0, 17, 3), fill=AMBER)
mark.save(f"{OUT}/phase_mark.png")

def sample(src_name, out_name, draws):
    im = Image.open(f"{OUT}/{src_name}").convert("RGBA")
    d = ImageDraw.Draw(im)
    for x, y, text, fill in draws:
        d.text((x, y), text, font=font(16), fill=fill)
    im.save(out_name)

sample("crt_asc.png", "/tmp/crt_preview_asc.png", [
    (524, 74, "0.21", GREEN),
    (524, 126, "1.4", GREEN),
    (524, 178, "1.62", GREEN),
    (524, 230, "62 / 65", GREEN),
    (524, 282, "2", GREEN),
    (524, 334, "840 / 910", GREEN),
    (48, 356, "PAD LOCK   12.4 km   18.0 km", GREEN),
])
sample("crt_vs.png", "/tmp/crt_preview_vs.png", [
    (524, 74, "-42", GREEN), (524, 126, "2.10", GREEN), (524, 178, "NOM 340", GREEN),
    (524, 230, "8.2 km", GREEN), (524, 282, "120 m", GREEN), (524, 334, "860", GREEN),
])
sample("crt_rte.png", "/tmp/crt_preview_rte.png", [
    (524, 74, "MUN", GREEN), (524, 126, "2.4 d", GREEN), (524, 178, "LANDER", GREEN),
    (524, 230, "1840", GREEN), (524, 282, "900", GREEN), (524, 334, "600", GREEN),
])
sample("crt_bdg.png", "/tmp/crt_preview_bdg.png", [
    (524, 74, "2400", GREEN), (524, 126, "80", GREEN), (524, 178, "150", GREEN),
    (524, 230, "860", GREEN), (524, 282, "900", GREEN), (524, 334, "600", GREEN),
])
sample("crt_glass.png", "/tmp/crt_preview_glass.png", [
    (32, 150, "245", GREEN), (578, 150, "12.4km", GREEN),
    (28, 348, "-12", GREEN), (190, 348, "ASCENT", GREEN),
    (350, 348, "LAUNCH", GREEN), (530, 348, "NOMINAL", GREEN),
])
print("plates ok")
