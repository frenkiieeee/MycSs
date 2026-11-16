#!/usr/bin/env python3
"""
MycSs mascot set generator.

Everything is drawn as clean SVG with hand-built paths (no tracing) and exported
to PNG. Geometry lives in "sketch space" (coordinates of the original brand board
crop, ~880x880) and each drawing maps it to its own canvas with a `Ctx`.

    python3 generate.py            # svg/ + png/ + palette.json

Outputs (flat folders, sizes in the file name):
    svg/mycss-<expresion>.svg          10 expressions, same frame so they swap 1:1
    svg/mycss-state-<estado>.svg        5 states / contexts
    svg/mycss-wordmark-on-{dark,light}.svg
    svg/mycss-logotype-on-{dark,light}.svg
    svg/mycss-icon-{cream,yellow,dark}.svg
    png/...-<px>.png                    transparent (icons have their own tile)

PNG export needs `rsvg-convert` (brew install librsvg) or ImageMagick.
The wordmark is outlined from Nunito ExtraBold (SIL OFL), shipped in fonts/;
needs `pip install fonttools` the first time.
"""
import json
import math
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
FONT = HERE / "fonts" / "nunito-latin-800-normal.woff"

# --- Palette (Frenkiieeee) -------------------------------------------------
INK = "#0B0B0F"        # outline, eye           (Fondo Principal)
SURFACE = "#1A1A22"    # elevated surface
CREAM = "#F7F4E8"      # body / text            (Texto / Mascota)
BORDER = "#3A3A46"     # borders / secondary
YELLOW = "#FFD400"     # primary                (Primario Frenkie)
SHADE = "#E8E0CB"      # soft shadow on the neck (derived from the sketch)
YELLOW_DK = "#E3AE00"  # folds / headphone cups  (derived)
SILVER = "#CBCBD8"     # laptop lid              (derived)

STROKE = 42.0          # outline width in sketch space

# --- Body geometry (sketch space) ------------------------------------------
# Centre line of the outline stroke, clockwise from the bottom-left. Extracted from
# the sketch (silhouette -> offset -> smoothed -> Beziers, ~1% area error); the
# chin/neck junction was redrawn by hand as a clean corner.
_BODY_CURVES = [
    [(169.9, 784.5), (215.4, 724.4), (225.5, 651.8)],
    [(236.6, 571.5), (190.3, 501.2), (194.3, 421.6)],
    [(200.1, 309.3), (261.1, 302.1), (312.1, 241.5)],
    [(367.7, 175.4), (367.5, 113.8), (474.7, 98.6)],
    [(582.3, 83.2), (641.5, 159.7), (702.6, 232.9)],
    [(742.4, 280.5), (788.4, 317), (807.1, 378.9)],
    [(845.6, 506), (743.2, 616.2), (619.5, 624.5)],
    [(596, 626.6), (572, 628.8), (548, 631)],
    [(530, 668), (497, 730), (497, 849)],
]
_START = (138.9, 849)
BODY = [("M", [_START])] + [("C", c) for c in _BODY_CURVES] + [("L", [_START]), ("Z", [])]
# Same body with the neck running off the canvas (app icons crop it).
BODY_LONG = ([("M", [(62.5, 1000)]), ("L", [_START])] + [("C", c) for c in _BODY_CURVES]
             + [("L", [(497, 1000)]), ("Z", [])])

SHADOW = [
    ("M", [(410, 522)]),
    ("C", [(430, 590), (466, 628), (468, 690)]),
    ("C", [(470, 750), (456, 800), (452, 849)]),
    ("L", [(497, 849)]),
    ("C", [(497, 730), (530, 668), (548, 631)]),
    ("L", [(572, 633)]),
    ("L", [(500, 618)]),
    ("L", [(440, 560)]),
    ("Z", []),
]
SHADOW_LONG = [("M", [(410, 522)]), ("C", [(430, 590), (466, 628), (468, 690)]),
               ("C", [(470, 760), (456, 900), (452, 1000)]), ("L", [(497, 1000)]),
               ("L", [(497, 849)]), ("C", [(497, 730), (530, 668), (548, 631)]),
               ("L", [(572, 633)]), ("L", [(500, 618)]), ("L", [(440, 560)]), ("Z", [])]

MOUTH = [("M", [(416, 496)]), ("C", [(432, 546), (480, 614), (572, 629)])]

E = (480, 297)          # eye centre
EYE_R = 94


# --- Tiny drawing toolkit ---------------------------------------------------
class Ctx:
    """Maps sketch space to a canvas: p' = p * s + (ox, oy)."""

    def __init__(self, s=1.0, ox=0.0, oy=0.0):
        self.s, self.ox, self.oy = s, ox, oy

    def p(self, pt):
        return pt[0] * self.s + self.ox, pt[1] * self.s + self.oy

    def d(self, path):
        out = []
        for cmd, pts in path:
            if cmd == "Z":
                out.append("Z")
            elif cmd == "A":
                rx, ry, rot, large, sweep, end = pts
                x, y = self.p(end)
                out.append(f"A {rx * self.s:.1f} {ry * self.s:.1f} {rot} {large} {sweep} {x:.1f} {y:.1f}")
            else:
                out.append(cmd + " " + " ".join("%.1f %.1f" % self.p(q) for q in pts))
        return " ".join(out)

    def path(self, path, fill="none", stroke=None, sw=0, id=None):
        a = f' id="{id}"' if id else ""
        st = f' stroke="{stroke}" stroke-width="{sw * self.s:.1f}"' if stroke else ""
        return f'<path{a} d="{self.d(path)}" fill="{fill}"{st}/>'

    def circle(self, c, r, fill="none", stroke=None, sw=0, id=None):
        x, y = self.p(c)
        a = f' id="{id}"' if id else ""
        st = f' stroke="{stroke}" stroke-width="{sw * self.s:.1f}"' if stroke else ""
        return f'<circle{a} cx="{x:.1f}" cy="{y:.1f}" r="{r * self.s:.1f}" fill="{fill}"{st}/>'


def pl(*pts, close=False):
    path = [("M", [pts[0]])] + [("L", [q]) for q in pts[1:]]
    return path + ([("Z", [])] if close else [])


def ellipse(cx, cy, rx, ry):
    return [("M", [(cx - rx, cy)]), ("A", [rx, ry, 0, 1, 1, (cx + rx, cy)]),
            ("A", [rx, ry, 0, 1, 1, (cx - rx, cy)]), ("Z", [])]


def group(id, *parts):
    inner = "\n    ".join(p for p in parts if p)
    return f'  <g id="{id}">\n    {inner}\n  </g>'


def svg(size, title, *groups, w=None, h=None, viewbox=None, defs=""):
    w, h = w or size, h or size
    vb = viewbox or f"0 0 {w} {h}"
    d = f"  <defs>{defs}</defs>\n" if defs else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}" width="{w}" height="{h}" role="img">\n'
            f'  <title>{title}</title>\n{d}'
            f'  <g stroke-linejoin="round" stroke-linecap="round">\n' + "\n".join(groups) + "\n  </g>\n</svg>\n")


# --- Body, mouth, eyes ------------------------------------------------------
def body(c, fill=CREAM, shade=SHADE, outline=INK, long=False):
    shape, sh = (BODY_LONG, SHADOW_LONG) if long else (BODY, SHADOW)
    parts = [c.path(shape, fill=fill, id="body-fill")]
    if shade:
        parts.append(c.path(sh, fill=shade, id="shadow"))
    if outline:
        parts.append(c.path(shape, stroke=outline, sw=STROKE, id="body-outline"))
    return parts


def mouth(c, color=INK, sw=STROKE):
    return c.path(MOUTH, stroke=color, sw=sw, id="mouth")


def eye_open(c, r=EYE_R):
    return group("eye", c.circle(E, r, INK), c.circle((E[0] + 32, E[1] - 44), 32, "#FFFFFF", id="glint"))


def eye_arc_up(c, hw=122, lift=96, dy=22, sw=34):
    x, y = E
    return group("eye", c.path([("M", [(x - hw, y + dy)]),
                                ("C", [(x - hw * .64, y + dy - lift), (x + hw * .64, y + dy - lift), (x + hw, y + dy)])],
                               stroke=INK, sw=sw))


def eye_arc_down(c, hw=114, depth=76, dy=-8, sw=34):
    x, y = E
    return group("eye", c.path([("M", [(x - hw, y + dy)]),
                                ("C", [(x - hw * .66, y + dy + depth), (x + hw * .66, y + dy + depth), (x + hw, y + dy)])],
                               stroke=INK, sw=sw))


def eye_lid_half(c):
    x, y = E
    lid_y = y - 24
    return group("eye",
                 c.path([("M", [(x - 84, lid_y)]), ("A", [84, 66, 0, 0, 0, (x + 84, lid_y)]), ("Z", [])], fill=INK),
                 c.path(pl((x - 112, lid_y), (x + 112, lid_y)), stroke=INK, sw=26),
                 c.circle((x + 40, y + 6), 15, "#FFFFFF", id="glint"))


def eye_focus(c, slope=0.16, lid=-40):
    x, y = E
    m, k, r = slope, lid, EYE_R
    a, b, cc = 1 + m * m, 2 * k * m, k * k - r * r
    disc = math.sqrt(b * b - 4 * a * cc)
    u1, u2 = (-b - disc) / (2 * a), (-b + disc) / (2 * a)
    p1, p2 = (x + u1, y + k + m * u1), (x + u2, y + k + m * u2)
    shape = [("M", [p1]), ("L", [p2]), ("A", [r, r, 0, 1, 1, p1]), ("Z", [])]
    ext = 16
    l1, l2 = (p1[0] - ext, p1[1] - ext * m), (p2[0] + ext, p2[1] + ext * m)
    return group("eye", c.path(shape, fill=INK), c.path(pl(l1, l2), stroke=INK, sw=24))


def star5(cx, cy, R, r):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return pl(*pts, close=True)


def eye_star(c):
    x, y = E
    return group("eye", c.circle((x, y), 102, INK),
                 c.path(star5(x, y + 4, 58, 25), fill="#FFFFFF", stroke="#FFFFFF", sw=9, id="star"))


def eye_surprised(c):
    return group("eye", c.circle(E, 104, INK), c.circle((E[0] + 36, E[1] - 46), 37, "#FFFFFF", id="glint"))


def eye_curious(c):
    return group("eye", c.circle((E[0] + 14, E[1] - 12), 96, INK),
                 c.circle((E[0] + 48, E[1] - 56), 33, "#FFFFFF", id="glint"))


# --- Extras (yellow accents, upper-right of the frame) ----------------------
def line(c, a, b, color=YELLOW, sw=24):
    return c.path(pl(a, b), stroke=color, sw=sw)


def ray(c, origin, deg, r0, r1, sw=26):
    t = math.radians(deg)
    pt = lambda r: (origin[0] + r * math.cos(t), origin[1] - r * math.sin(t))
    return line(c, pt(r0), pt(r1), sw=sw)


RAY_ORIGIN = (790, 232)


def x_rays2(c):
    return group("extras", ray(c, RAY_ORIGIN, 70, 120, 205), ray(c, RAY_ORIGIN, 27, 125, 192))


def x_rays3(c):
    return group("extras", ray(c, RAY_ORIGIN, 105, 120, 208), ray(c, RAY_ORIGIN, 66, 120, 208),
                 ray(c, RAY_ORIGIN, 27, 125, 192))


def x_dots(c):
    return group("extras", *[c.circle((x, 100), 22, YELLOW) for x in (790, 868, 946)])


def sparkle(cx, cy, h):
    k = h * 0.2
    return [("M", [(cx, cy - h)]), ("Q", [(cx + k, cy - k), (cx + h, cy)]), ("Q", [(cx + k, cy + k), (cx, cy + h)]),
            ("Q", [(cx - k, cy + k), (cx - h, cy)]), ("Q", [(cx - k, cy - k), (cx, cy - h)]), ("Z", [])]


def x_sparkles(c):
    return group("extras", c.path(sparkle(800, 105, 88), fill=YELLOW, stroke=YELLOW, sw=8),
                 c.path(sparkle(905, 215, 44), fill=YELLOW, stroke=YELLOW, sw=6))


def x_zz(c):
    return group("extras", c.path(pl((860, 45), (945, 45), (860, 130), (945, 130)), stroke=YELLOW, sw=26),
                 c.path(pl((790, 160), (848, 160), (790, 222), (848, 222)), stroke=YELLOW, sw=22))


def x_question(c):
    hook = [("M", [(845, 95)]), ("C", [(845, 20), (960, 20), (960, 90)]), ("C", [(960, 135), (905, 140), (905, 190)])]
    return group("extras", c.path(hook, stroke=YELLOW, sw=28), c.circle((905, 240), 19, YELLOW))


EXPRESSIONS = {
    "neutro":      (eye_open, None, "Neutro"),
    "feliz":       (lambda c: eye_arc_up(c), x_rays2, "Feliz"),
    "sorprendido": (eye_surprised, x_rays3, "Sorprendido"),
    "pensando":    (eye_lid_half, x_dots, "Pensando"),
    "guino":       (lambda c: eye_arc_up(c, hw=104, lift=74, dy=26), x_rays2, "Guiño"),
    "emocionado":  (eye_star, x_sparkles, "Emocionado"),
    "enfocado":    (eye_focus, None, "Enfocado"),
    "relajado":    (eye_arc_down, None, "Relajado"),
    "durmiendo":   (lambda c: eye_arc_down(c, hw=126, depth=72, dy=14), x_zz, "Durmiendo"),
    "curioso":     (eye_curious, x_question, "Curioso"),
}


def expression_svg(name, size=512):
    eye_fn, extra_fn, label = EXPRESSIONS[name]
    s = size / 900
    c = Ctx(s, -80 * s, 0)                       # frame: sketch x 80..980, y 0..900
    groups = [group("body", *body(c), mouth(c)), eye_fn(c)]
    if extra_fn:
        groups.append(extra_fn(c))
    return svg(size, f"MycSs - {label}", *groups)


# --- States / contexts (512 canvas) -----------------------------------------
def hand(c, cx, cy, rx, ry, sw=16):
    return c.path(ellipse(cx, cy, rx, ry), fill=CREAM, stroke=INK, sw=sw)


def state_asomando():
    c = Ctx()
    dome = [("M", [(72, 440)]), ("C", [(72, 330), (128, 236), (220, 208)]),
            ("C", [(264, 194), (324, 204), (364, 246)]), ("C", [(412, 294), (440, 366), (440, 440)])]
    return svg(512, "MycSs - Asomando",
               group("body", c.path(dome + [("Z", [])], fill=CREAM), c.path(dome, stroke=INK, sw=22),
                     c.path(pl((34, 444), (478, 444)), stroke=YELLOW, sw=10)),
               group("eye", c.circle((236, 312), 50, INK), c.circle((253, 290), 17, "#FFFFFF", id="glint")),
               group("hands", hand(c, 148, 442, 52, 30), hand(c, 364, 442, 52, 30)),
               group("extras", line(c, (372, 100), (388, 142), sw=20), line(c, (410, 148), (452, 164), sw=20)))


def state_portatil():
    b = Ctx(0.43, -14.3, 2)
    c = Ctx()
    slab = pl((28, 352), (456, 338), (474, 372), (28, 382), close=True)
    lid = pl((262, 212), (478, 184), (446, 336), (226, 342), close=True)
    return svg(512, "MycSs - Portátil",
               group("body", *body(b), mouth(b)), eye_open(b),
               group("laptop", c.path(slab, fill="#B9B9C8", stroke=INK, sw=18),
                     c.path(lid, fill=SILVER, stroke=INK, sw=18),
                     group("logo-mark", c.circle((352, 270), 17, INK), c.circle((358, 263), 6, "#FFFFFF"))))


def state_auriculares():
    b = Ctx(0.5, 19.5, 20.5)
    c = Ctx()
    band = [("M", [(126, 206)]), ("C", [(96, 20), (400, -45), (400, 190)])]
    note = [c.circle((436, 86), 13, YELLOW), c.circle((482, 78), 13, YELLOW),
            c.path(pl((447, 84), (447, 42)), stroke=YELLOW, sw=8),
            c.path(pl((493, 76), (493, 34)), stroke=YELLOW, sw=8),
            c.path(pl((447, 42), (493, 34)), stroke=YELLOW, sw=12)]
    return svg(512, "MycSs - Auriculares",
               group("headphones-band", c.path(band, stroke=INK, sw=40), c.path(band, stroke=YELLOW, sw=24)),
               group("body", *body(b), mouth(b)), eye_arc_up(b),
               group("headphones-cup", c.circle((132, 248), 52, YELLOW, INK, 16), c.circle((132, 248), 28, YELLOW_DK)),
               group("music", *note))


def state_cafe():
    b = Ctx(0.5, -28.5, 0.5)
    c = Ctx()
    arm = [("M", [(214, 438)]), ("C", [(256, 442), (304, 424), (340, 392)])]
    mug = c.path([("M", [(372, 296)]), ("L", [(452, 296)]), ("L", [(452, 376)]),
                  ("Q", [(452, 392), (436, 392)]), ("L", [(388, 392)]), ("Q", [(372, 392), (372, 376)]), ("Z", [])],
                 fill=CREAM, stroke=INK, sw=15)
    handle = c.path([("M", [(452, 318)]), ("C", [(494, 312), (496, 372), (452, 368)])], stroke=INK, sw=15)
    steam = [c.path([("M", [(398, 268)]), ("C", [(382, 250), (414, 238), (398, 214)])], stroke=YELLOW, sw=10),
             c.path([("M", [(428, 268)]), ("C", [(412, 250), (444, 238), (428, 214)])], stroke=YELLOW, sw=10)]
    fingers = [c.path([("M", [(366, 366)]), ("C", [(380, 372), (392, 370), (398, 360)])], stroke=INK, sw=7),
               c.path([("M", [(372, 386)]), ("C", [(386, 392), (398, 390), (404, 380)])], stroke=INK, sw=7)]
    return svg(512, "MycSs - Café",
               group("mug", handle, mug, *steam),
               group("arm", c.path(arm, stroke=INK, sw=72), c.path(arm, stroke=CREAM, sw=50),
                     hand(c, 352, 384, 56, 46, sw=15), *fingers),
               group("body", *body(b), mouth(b)), eye_arc_down(b))


def state_manta():
    c = Ctx()
    hood = [("M", [(40, 470)]), ("C", [(38, 390), (96, 346), (140, 318)]), ("C", [(118, 188), (190, 74), (316, 64)]),
            ("C", [(430, 56), (486, 150), (478, 286)]), ("C", [(474, 380), (482, 430), (484, 470)]), ("Z", [])]
    face = [("M", [(196, 274)]), ("C", [(188, 196), (250, 152), (318, 160)]), ("C", [(388, 168), (410, 230), (398, 290)]),
            ("C", [(388, 340), (304, 354), (250, 336)]), ("C", [(214, 324), (200, 302), (196, 274)]), ("Z", [])]
    lap = [("M", [(40, 470)]), ("C", [(74, 392), (170, 350), (270, 366)]), ("C", [(360, 380), (440, 372), (484, 334)]),
           ("L", [(484, 470)]), ("Z", [])]
    folds = [c.path([("M", [(70, 440)]), ("C", [(110, 408), (160, 400), (210, 410)])], stroke=YELLOW_DK, sw=10),
             c.path([("M", [(300, 410)]), ("C", [(360, 420), (420, 410), (462, 380)])], stroke=YELLOW_DK, sw=10)]
    eye = c.path([("M", [(292, 226)]), ("C", [(306, 258), (354, 258), (368, 226)])], stroke=INK, sw=12)
    return svg(512, "MycSs - Manta",
               group("blanket-back", c.path(hood, fill=YELLOW, stroke=INK, sw=22),
                     c.path([("M", [(160, 300)]), ("C", [(170, 210), (220, 120), (300, 100)])], stroke=YELLOW_DK, sw=10)),
               group("face", c.path(face, fill=CREAM, stroke=INK, sw=16), group("eye", eye)),
               group("blanket-front", c.path(lap, fill=YELLOW, stroke=INK, sw=22), *folds))


STATES = {"asomando": (state_asomando, "Asomando"), "portatil": (state_portatil, "Portátil"),
          "auriculares": (state_auriculares, "Auriculares"), "cafe": (state_cafe, "Café"),
          "manta": (state_manta, "Manta")}


# --- Wordmark, logotype, icons ----------------------------------------------
def outline_text(text, cap_h, x0=0.0, baseline=0.0, tracking=0.0):
    """Outline `text` from FONT into one SVG path. Returns (d, bbox)."""
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont
    f = TTFont(FONT)
    gs, cmap = f.getGlyphSet(), f.getBestCmap()
    sc = cap_h / (f["OS/2"].sCapHeight or 0.7 * f["head"].unitsPerEm)
    x, ds, bb = x0, [], [1e9, 1e9, -1e9, -1e9]
    for ch in text:
        g = gs[cmap[ord(ch)]]
        tf = (sc, 0, 0, -sc, x, baseline)
        pen = SVGPathPen(gs, ntos=lambda v: f"{v:.1f}")
        g.draw(TransformPen(pen, tf))
        ds.append(pen.getCommands())
        bp = BoundsPen(gs)
        g.draw(TransformPen(bp, tf))
        if bp.bounds:
            bb = [min(bb[0], bp.bounds[0]), min(bb[1], bp.bounds[1]), max(bb[2], bp.bounds[2]), max(bb[3], bp.bounds[3])]
        x += g.width * sc + tracking * cap_h
    return " ".join(ds), bb


def wordmark_svg(color, pad=24):
    d, bb = outline_text("MycSs", 200, tracking=-0.01)
    w, h = bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad
    vb = f"{bb[0] - pad:.1f} {bb[1] - pad:.1f} {w:.1f} {h:.1f}"
    return svg(0, "MycSs", group("wordmark", f'<path d="{d}" fill="{color}"/>'), w=round(w), h=round(h), viewbox=vb)


def logotype_svg(color):
    s, H = 0.48, 420
    c = Ctx(s, 36 - 117 * s, 20 - 79 * s)
    d, bb = outline_text("MycSs", 168, x0=430, baseline=222, tracking=-0.01)
    W = round(bb[2] + 40)
    return svg(0, "MycSs", group("mark", *body(c), mouth(c), eye_open(c)),
               group("wordmark", f'<path d="{d}" fill="{color}"/>'), w=W, h=H)


def icon_svg(kind, size=512):
    rx = size * 0.2237
    c = Ctx(0.55, -5.9, 12.5)
    tile_clip = f'<clipPath id="tile"><rect width="{size}" height="{size}" rx="{rx:.1f}"/></clipPath>'
    if kind == "cream":
        bg = f'<rect width="{size}" height="{size}" rx="{rx:.1f}" fill="{CREAM}"/>'
        art = [*body(c, fill="#FFFFFF", long=True), mouth(c), eye_open(c)]
    elif kind == "yellow":
        bg = f'<rect width="{size}" height="{size}" rx="{rx:.1f}" fill="{YELLOW}"/>'
        art = [c.path(BODY_LONG, fill=INK, stroke=INK, sw=STROKE, id="silhouette"),
               c.circle((512, 253), 36, CREAM, id="glint")]
    else:
        bg = (f'<rect width="{size}" height="{size}" rx="{rx:.1f}" fill="{INK}"/>'
              f'<rect x="3" y="3" width="{size - 6}" height="{size - 6}" rx="{rx - 3:.1f}" fill="none" stroke="{CREAM}" stroke-width="5"/>')
        art = [c.path(BODY_LONG, stroke=CREAM, sw=22, id="body-outline"),
               c.path(MOUTH, stroke=CREAM, sw=22, id="mouth"),
               c.circle(E, 88, "none", CREAM, 20, id="eye"),
               c.circle((512, 253), 26, CREAM, id="glint")]
    return svg(size, f"MycSs - icono {kind}", group("tile", bg),
               '  <g id="art" clip-path="url(#tile)">\n    ' + "\n    ".join(art) + "\n  </g>", defs=tile_clip)


# --- Export -----------------------------------------------------------------
def to_png(svg_path, png_path, width, height=None):
    height = height or width
    if shutil.which("rsvg-convert"):
        cmd = ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(png_path), str(svg_path)]
    elif shutil.which("magick"):
        cmd = ["magick", "-background", "none", "-density", "384", str(svg_path), "-resize", f"{width}x{height}", str(png_path)]
    else:
        print("  ! no rsvg-convert/magick: skipped", png_path.name)
        return
    subprocess.run(cmd, check=True)


def build():
    svg_dir, png_dir = HERE / "svg", HERE / "png"
    svg_dir.mkdir(exist_ok=True)
    png_dir.mkdir(exist_ok=True)
    items = []   # (name, svg text, png widths)
    for k in EXPRESSIONS:
        items.append((f"mycss-{k}", expression_svg(k), (1024, 512, 256, 128)))
    for k, (fn, _) in STATES.items():
        items.append((f"mycss-state-{k}", fn(), (1024, 512, 256, 128)))
    for kind in ("cream", "yellow", "dark"):
        items.append((f"mycss-icon-{kind}", icon_svg(kind), (1024, 512, 256, 128, 64, 32)))
    if FONT.exists():
        items.append(("mycss-wordmark-on-dark", wordmark_svg(CREAM), (1600, 800, 400)))
        items.append(("mycss-wordmark-on-light", wordmark_svg(INK), (1600, 800, 400)))
        items.append(("mycss-logotype-on-dark", logotype_svg(CREAM), (1600, 800, 400)))
        items.append(("mycss-logotype-on-light", logotype_svg(INK), (1600, 800, 400)))
    else:
        print("! fonts/ missing, wordmark and logotype skipped")
    for name, text, widths in items:
        p = svg_dir / f"{name}.svg"
        p.write_text(text, encoding="utf-8")
        m = re.search(r'width="(\d+)" height="(\d+)"', text)
        ratio = int(m.group(2)) / int(m.group(1))
        for w in widths:
            to_png(p, png_dir / f"{name}-{w}.png", w, round(w * ratio))
        print("ok", name)
    (HERE / "palette.json").write_text(json.dumps({
        "primary": YELLOW, "background": INK, "surface": SURFACE, "mascot": CREAM, "border": BORDER,
        "derived": {"shade": SHADE, "yellowDark": YELLOW_DK, "silver": SILVER}}, indent=2) + "\n")


if __name__ == "__main__":
    build()
