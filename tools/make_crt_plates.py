#!/usr/bin/env python3
"""Pixel-aligned AOSO CRT plates. Plot rectangle must match ui2_plots.ks."""
from pathlib import Path
from tempfile import gettempdir
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = str(Path(__file__).resolve().parents[1] / "AOSO" / "ux" / "ui2_assets")
W, H = 740, 400
OX, OY, PW, PH = 36, 52, 460, 280
FONT = next(p for p in (
    "C:/Windows/Fonts/consolab.ttf",
    "C:/Windows/Fonts/lucon.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
) if Path(p).is_file())
PREVIEW = Path(gettempdir())
GREEN = (118, 255, 150, 255)
DIM = (36, 110, 64, 255)
AMBER = (255, 176, 46, 255)
YELLOW = (255, 214, 70, 255)
BLUE = (80, 190, 255, 255)
GRAY = (150, 155, 150, 255)
RED = (255, 90, 70, 255)
BLACK = (3, 6, 4, 255)
GRID = (28, 72, 44, 255)

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

def instrument_base(title, center):
    """840x560 instrument face; the GUI window supplies the key row below."""
    im = Image.new("RGBA", (840, 560), BLACK)
    d = ImageDraw.Draw(im)
    for inset, shade in ((0, (29, 31, 30, 255)), (3, (82, 85, 82, 255)),
                         (8, (36, 39, 37, 255)), (14, (14, 18, 16, 255)),
                         (22, (53, 58, 54, 255)), (27, (4, 9, 7, 255))):
        d.rounded_rectangle((inset, inset, 839-inset, 559-inset),
                            radius=max(8, 27-inset//2), fill=shade)
    d.rounded_rectangle((31, 31, 808, 528), radius=13, fill=(2, 8, 6, 255),
                        outline=(37, 75, 48, 255), width=2)
    for sx in (13, 826):
        for sy in (13, 546):
            d.ellipse((sx-4, sy-4, sx+4, sy+4), fill=(10, 12, 11, 255),
                      outline=(118, 120, 116, 255))
            d.line((sx-2, sy+1, sx+2, sy-1), fill=(110, 112, 108, 255))
    glow_text(im, (63, 47), title, GREEN, 22)
    d = ImageDraw.Draw(im)
    d.text((420, 50), center, font=font(19), fill=GREEN, anchor="mt")
    d.text((656, 48), "MET", font=font(16), fill=DIM)
    d.line((62, 93, 778, 93), fill=GREEN, width=1)
    return im, d


def instrument_plot(d, rect, divisions_x=4, divisions_y=4):
    x0, y0, x1, y1 = rect
    d.line((x0, y0, x0, y1, x1, y1), fill=GRAY, width=2)
    d.line((x0, y0, x1, y0, x1, y1), fill=DIM)
    for i in range(1, divisions_x):
        x = x0 + (x1-x0)*i/divisions_x
        d.line((x, y0, x, y1), fill=GRID)
    for i in range(1, divisions_y):
        y = y0 + (y1-y0)*i/divisions_y
        d.line((x0, y, x1, y), fill=GRID)
    for i in range(divisions_x+1):
        x = x0 + (x1-x0)*i/divisions_x
        d.line((x, y1-5, x, y1+5), fill=GRAY)
    for i in range(divisions_y+1):
        y = y0 + (y1-y0)*i/divisions_y
        d.line((x0-5, y, x0+5, y), fill=GRAY)


def vertical_title(im, word, x, y):
    txt = Image.new("RGBA", (200, 20), (0, 0, 0, 0))
    ImageDraw.Draw(txt).text((0, 0), word, font=font(14), fill=GREEN)
    rotated = txt.rotate(90, expand=True)
    im.alpha_composite(rotated, (x, y))


def asc_plate():
    im, d = instrument_base("ASC TRAJ", "AOSO")
    instrument_plot(d, (145, 145, 595, 445), 4, 4)
    vertical_title(im, "ALTITUDE km", 50, 211)
    d = ImageDraw.Draw(im)
    d.text((345, 484), "DOWNRANGE km", font=font(17), fill=GREEN)
    d.text((80, 145), "Q", font=font(14), fill=GREEN)
    d.text((76, 161), "kPa", font=font(12), fill=DIM)
    d.rectangle((82, 182, 104, 412), outline=DIM)
    for q in range(0, 41, 10):
        y = 409 - q/40*224
        d.line((104, y, 113, y), fill=DIM)
        d.text((74, y-5), str(q), font=font(10), fill=DIM, anchor="rm")
    rows = ((151, "Q  kPa"), (196, "AoA  deg"), (241, "TWR"),
            (286, "PITCH CMD"), (331, "STAGE"),
            (386, "LF LEFT"), (431, "BEST"))
    for y, word in rows:
        d.text((624, y), word, font=font(14), fill=GREEN)
    for y in (369, 414, 460):
        d.line((624, y, 794, y), fill=DIM)
    scanlines(im)
    im.save(f"{OUT}/crt_asc.png")


def vs_plate():
    im, d = instrument_base("VSIT / ENERGY", "BODY")
    instrument_plot(d, (112, 127, 620, 348), 4, 4)
    vertical_title(im, "ALTITUDE km", 48, 177)
    d = ImageDraw.Draw(im)
    d.text((335, 372), "RANGE TO SITE km", font=font(16), fill=GREEN)
    d.text((665, 125), "dV MARGIN", font=font(14), fill=GREEN)
    d.rectangle((681, 161, 694, 350), outline=DIM)
    d.rectangle((682, 162, 693, 223), fill=(31, 95, 46, 255))
    d.rectangle((682, 224, 693, 285), fill=(136, 93, 28, 255))
    d.rectangle((682, 286, 693, 349), fill=(100, 34, 30, 255))
    for y, word, col in ((171, "NOM", GREEN), (248, "MARGIN", AMBER),
                         (323, "ABORT", RED)):
        d.line((696, y, 705, y), fill=col)
        d.text((711, y-8), word, font=font(12), fill=col)
    d.rectangle((91, 387, 299, 480), outline=DIM)
    d.text((107, 390), "SITE POLAR MAP", font=font(12), fill=GREEN)
    cx, cy = 196, 445
    for radius in (17, 34):
        d.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), outline=DIM)
    d.line((cx-38, cy, cx+38, cy), fill=DIM)
    d.line((cx, cy-38, cx, cy+38), fill=DIM)
    d.line((cx-24, cy-24, cx+24, cy+24), fill=GRID)
    d.line((cx-24, cy+24, cx+24, cy-24), fill=GRID)
    d.text((191, 405), "N", font=font(10), fill=GREEN)
    d.text((306, 390), "SITE / PE", font=font(12), fill=DIM)
    d.line((62, 487, 778, 487), fill=DIM)
    metrics = ("HDOT", "TGT HDOT", "TWR", "SITE", "ELEV", "FUEL LAND", "RESERVE")
    for i, word in enumerate(metrics):
        x = 66 + i*103
        d.text((x, 493), word, font=font(11), fill=GREEN)
        if i:
            d.line((x-7, 493, x-7, 524), fill=DIM)
    scanlines(im)
    im.save(f"{OUT}/crt_vs.png")

def rte_curves(d, x0, y0, pw, ph):
    def ms_y(ms):
        ms = max(0, min(8000, ms))
        return y0 + ph - (ms / 8000.0) * ph

    def u_curve(bottom, col, label):
        pts = []
        for i in range(81):
            t = i / 80.0
            u = abs(t - 0.5) * 2.0
            u = u ** 1.55
            ms = bottom + (8000 - bottom) * u
            pts.append((x0 + t * pw, ms_y(ms)))
        d.line(pts, fill=col, width=1)
        d.text((x0 + int(0.66 * pw), ms_y(bottom + (8000 - bottom) * 0.28) - 10), label, font=font(10), fill=col)

    u_curve(500, (40, 125, 72, 255), "500")
    u_curve(1000, (52, 155, 88, 255), "1000")
    u_curve(1800, (70, 185, 108, 255), "1800")
    u_curve(2800, (92, 215, 128, 255), "2800")
    u_curve(4200, (120, 235, 150, 255), "4200")


def route_plate():
    """Concept ribbon + transfer-cost plot. Live text is pinned in ui2_plots.ks.

    Header values: hop (20,58), window (300,58), dV (560,54).
    Pills: (16+i*90, 88, 74, 26). Tags under them at y=116.
    Plot: origin (70, 186), size 400 x 158, x 0..70 days, y 0..8000 m/s.
    Right card values start at x=526.
    """
    im = Image.new("RGBA", (W, H), BLACK)
    d = ImageDraw.Draw(im)
    bezel(d)
    glow_text(im, (18, 8), "MSN ROUTE / WINDOWS", GREEN, 18)
    d = ImageDraw.Draw(im)
    d.line((16, 40, 724, 40), fill=DIM)
    d.text((20, 46), "CURRENT HOP", font=font(11), fill=DIM)
    d.text((300, 46), "WINDOW", font=font(11), fill=DIM)
    d.text((548, 46), "dV", font=font(11), fill=DIM)

    for i in range(7):
        ax = 16 + i * 90 + 78
        d.line((ax, 100, ax + 8, 100), fill=GREEN)
        d.polygon([(ax + 8, 96), (ax + 12, 100), (ax + 8, 104)], fill=GREEN)

    d.text((18, 134), "LEGEND", font=font(11), fill=DIM)
    legend = (
        (88, GREEN, "CAPABLE"),
        (196, AMBER, "MARGIN"),
        (310, BLUE, "ORBIT ONLY"),
        (440, GRAY, "SKIP"),
        (530, YELLOW, "CURRENT"),
    )
    for x, col, word in legend:
        d.ellipse((x, 136, x + 8, 144), fill=col)
        d.text((x + 12, 134), word, font=font(11), fill=col)

    d.rounded_rectangle((14, 156, 500, 386), radius=8, outline=GREEN)
    d.text((26, 162), "TRANSFER COST", font=font(13), fill=GREEN)
    d.text((168, 164), "m/s", font=font(11), fill=DIM)
    x0, y0, pw, ph = 70, 186, 400, 158
    for frac, lab in ((0, "0"), (0.25, "2k"), (0.5, "4k"), (0.75, "6k"), (1, "8k")):
        y = int(y0 + ph - frac * ph)
        d.line((x0, y, x0 + pw, y), fill=GRID)
        d.text((x0 - 28, y - 6), lab, font=font(10), fill=DIM)
    for day in range(0, 71, 10):
        x = int(x0 + day / 70.0 * pw)
        d.line((x, y0, x, y0 + ph), fill=GRID)
        d.text((x - 8, y0 + ph + 2), str(day), font=font(10), fill=DIM)
    rte_curves(d, x0, y0, pw, ph)
    d.text((x0 + 78, y0 + ph + 16), "DAYS FROM WINDOW OPEN", font=font(11), fill=GREEN)

    d.rounded_rectangle((512, 156, 724, 386), radius=8, outline=GREEN)
    d.text((526, 176), "LEFTOVER AFTER HOP", font=font(11), fill=DIM)
    d.line((526, 230, 708, 230), fill=DIM)
    d.text((526, 236), "RETURN", font=font(11), fill=DIM)
    d.line((526, 278, 708, 278), fill=DIM)
    d.text((526, 284), "ABORT", font=font(11), fill=DIM)
    d.line((526, 324, 708, 324), fill=DIM)
    d.text((526, 330), "CLASS", font=font(11), fill=DIM)
    d.text((526, 358), "CONF", font=font(11), fill=DIM)
    scanlines(im)
    im.save(f"{OUT}/crt_rte.png")
    print("crt_rte", x0, y0, pw, ph)


def vdash(d, x, y0, y1):
    y = y0
    while y < y1:
        d.line((x, y, x, min(y + 4, y1)), fill=DIM)
        y += 8


def budget_plate():
    """Concept waterfall + ledger. Live pins are in ui2_plots.ks.

    Waterfall columns x = 22 + i*76, names y=66, values y=172.
    Bar field y=88..168 (0 m/s on the bottom).
    Table rows y = 232 + i*24.
    """
    im = Image.new("RGBA", (W, H), BLACK)
    d = ImageDraw.Draw(im)
    bezel(d)
    glow_text(im, (18, 8), "BUDGET / PROJECTED STATE", GREEN, 18)
    d = ImageDraw.Draw(im)

    d.rounded_rectangle((14, 42, 500, 210), radius=8, outline=GREEN)
    d.text((24, 48), "DELTA-V WATERFALL", font=font(12), fill=GREEN)
    d.text((200, 50), "m/s", font=font(11), fill=DIM)
    d.line((28, 182, 486, 182), fill=DIM)
    for i in range(1, 6):
        vdash(d, 22 + i * 76 - 4, 64, 182)

    d.rounded_rectangle((14, 218, 500, 386), radius=8, outline=GREEN)
    d.text((24, 224), "MISSION STEP", font=font(11), fill=DIM)
    d.text((156, 224), "STATUS", font=font(11), fill=DIM)
    d.text((260, 224), "NOTES", font=font(11), fill=DIM)
    d.line((24, 240, 486, 240), fill=DIM)
    for i in range(1, 6):
        y = 242 + i * 22
        d.line((24, y, 486, y), fill=GRID)

    d.rounded_rectangle((512, 42, 726, 188), radius=8, outline=GREEN)
    d.text((524, 48), "MISSION-USABLE dV", font=font(12), fill=GREEN)
    d.rounded_rectangle((524, 100, 710, 112), radius=3, outline=DIM)
    d.text((524, 118), "UNUSABLE", font=font(11), fill=DIM)
    d.text((524, 140), "RESERVE", font=font(11), fill=DIM)
    d.text((524, 162), "LANDING", font=font(11), fill=DIM)
    for y in (122, 144, 166):
        d.rounded_rectangle((648, y, 710, y + 8), radius=2, outline=DIM)

    d.rounded_rectangle((512, 196, 726, 308), radius=8, outline=GREEN)
    d.text((524, 202), "RETURN ALLOCATION", font=font(12), fill=AMBER)
    d.rounded_rectangle((524, 246, 710, 258), radius=2, outline=DIM)
    d.text((524, 266), "ABORT ALLOCATION", font=font(11), fill=GREEN)
    d.rounded_rectangle((524, 286, 710, 296), radius=2, outline=DIM)

    d.rounded_rectangle((512, 316, 726, 386), radius=8, outline=GREEN)
    d.text((524, 326), "CRT TIME", font=font(11), fill=DIM)
    d.text((524, 356), "SYS STATUS", font=font(11), fill=DIM)
    d.ellipse((696, 358, 706, 368), outline=GREEN)

    scanlines(im)
    im.save(f"{OUT}/crt_bdg.png")
    print("crt_bdg")


asc_plate()
vs_plate()
route_plate()
budget_plate()
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


def capsule(name, outline):
    im = Image.new("RGBA", (74, 26), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((1, 1, 72, 24), radius=11, outline=outline, width=2)
    im.save(f"{OUT}/{name}")


capsule("pill_now.png", YELLOW)
capsule("pill_next.png", GREEN)
capsule("pill_cap.png", GREEN)
capsule("pill_mar.png", AMBER)
capsule("pill_orb.png", BLUE)
capsule("pill_skip.png", GRAY)
capsule("pill_done.png", DIM)
capsule("pill_bad.png", RED)


def flat_bar(name, fill):
    im = Image.new("RGBA", (32, 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 31, 9), radius=2, fill=fill)
    im.save(f"{OUT}/{name}")


flat_bar("bar_go.png", GREEN)
flat_bar("bar_warn.png", AMBER)
flat_bar("bar_bad.png", RED)

tri = Image.new("RGBA", (14, 14), (0, 0, 0, 0))
ImageDraw.Draw(tri).polygon([(7, 1), (13, 13), (1, 13)], outline=AMBER)
ImageDraw.Draw(tri).text((5, 3), "!", font=font(8), fill=AMBER)
tri.save(f"{OUT}/warn_tri.png")

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

sample("crt_asc.png", str(PREVIEW / "crt_preview_asc.png"), [
    (696, 47, "00:02:41", GREEN),
    (710, 148, "18.4", GREEN), (710, 193, "2.1", GREEN),
    (710, 238, "1.42", GREEN), (710, 283, "62/65", GREEN),
    (710, 328, "2", GREEN), (710, 383, "1840", GREEN),
    (710, 428, "1760", GREEN),
    (146, 509, "PAD LOCK  DR 12.4 km  ALT 18.0 km", GREEN),
])
sample("crt_vs.png", str(PREVIEW / "crt_preview_vs.png"), [
    (476, 47, "MUN", GREEN), (696, 47, "01:14:08", GREEN),
    (660, 365, "+340 m/s", GREEN), (308, 413, "RADAR 210 m", GREEN),
    (308, 441, "BURN  SITE 12.4 km", GREEN),
    (66, 507, "-42 m/s", GREEN), (169, 507, "---", GREEN),
    (272, 507, "1.8", GREEN), (375, 507, "12.4 km", GREEN),
    (478, 507, "+210 m", GREEN), (581, 507, "620 m/s", GREEN),
    (684, 507, "180 m/s", GREEN),
])
def mock(src, dest, draws):
    im = Image.open(f"{OUT}/{src}").convert("RGBA")
    d = ImageDraw.Draw(im)
    for item in draws:
        x, y, text, fill, size = item
        d.text((x, y), text, font=font(size), fill=fill)
    im.save(dest)


mock("crt_rte.png", str(PREVIEW / "crt_preview_rte.png"), [
    (500, 12, "HOPPER", AMBER, 13),
    (20, 58, "KERBIN > MINMUS", GREEN, 14),
    (300, 58, "LOCAL HOP", GREEN, 14),
    (560, 54, "860", YELLOW, 16),
    (24, 94, "MINMUS", YELLOW, 12),
    (114, 94, "DRES", GREEN, 12),
    (204, 94, "DUNA", GREEN, 12),
    (294, 94, "IKE", GREEN, 12),
    (384, 94, "EVE", BLUE, 12),
    (474, 94, "GILLY", GREEN, 12),
    (564, 94, "JOOL", BLUE, 12),
    (654, 94, "LAYTHE", GRAY, 12),
    (526, 160, "FEASIBLE", GREEN, 12),
    (526, 192, "5153 m/s", GREEN, 22),
    (526, 250, "0 m/s", GREEN, 16),
    (526, 298, "200 m/s", GREEN, 16),
    (526, 340, "hopper", GREEN, 13),
    (600, 354, "1.00", GREEN, 16),
])
# diamond sample at day 0, 80 m/s -> bottom-left of plot
dpreview = Image.open(PREVIEW / "crt_preview_rte.png").convert("RGBA")
ImageDraw.Draw(dpreview).polygon([(78, 336), (88, 346), (78, 356), (68, 346)], outline=YELLOW)
dpreview.save(PREVIEW / "crt_preview_rte.png")

mock("crt_bdg.png", str(PREVIEW / "crt_preview_bdg.png"), [
    (24, 66, "NOW", GREEN, 11),
    (100, 66, "MINMUS", GREEN, 11),
    (176, 66, "MUN", GREEN, 11),
    (252, 66, "DRES", AMBER, 11),
    (328, 66, "DUNA", GREEN, 11),
    (404, 66, "END", RED, 11),
    (24, 186, "5160", GREEN, 11),
    (100, 186, "5153", GREEN, 11),
    (176, 186, "4693", GREEN, 11),
    (252, 186, "4866", AMBER, 11),
    (328, 186, "3693", GREEN, 11),
    (404, 186, "-3840", RED, 11),
    (24, 246, "NOW", GREEN, 12),
    (156, 246, "FEASIBLE", GREEN, 11),
    (260, 246, "---", GREEN, 12),
    (24, 268, "MINMUS+", GREEN, 12),
    (156, 268, "FEASIBLE", GREEN, 11),
    (260, 268, "MARGIN 5153", GREEN, 12),
    (24, 356, "END", RED, 12),
    (156, 356, "FAIL", RED, 11),
    (260, 356, "EVE", RED, 12),
    (524, 66, "5160 m/s", GREEN, 22),
    (590, 116, "0", GREEN, 12),
    (590, 138, "596", GREEN, 12),
    (590, 160, "0", GREEN, 12),
    (620, 214, "0 m/s", AMBER, 16),
    (640, 264, "200 m/s", GREEN, 14),
    (620, 328, "0:12:04", GREEN, 13),
    (620, 354, "PRELAUNCH", GREEN, 13),
])
sample("crt_glass.png", str(PREVIEW / "crt_preview_glass.png"), [
    (32, 150, "245", GREEN), (578, 150, "12.4km", GREEN),
    (28, 348, "-12", GREEN), (190, 348, "ASCENT", GREEN),
    (350, 348, "LAUNCH", GREEN), (530, 348, "NOMINAL", GREEN),
])
print("plates ok")
