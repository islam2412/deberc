#!/usr/bin/env python3
"""Иконка «Деберца» в оформлении КЧР: карты рисуются по той же геометрии, что в игре
(Deberc/Views/Cards/CardGeometry.swift), с портретами из art-raw/ (исходники Higgsfield 2K).

    python3 scripts/icon/render_kchr_icon.py preview <папка>   # варианты для выбора
    python3 scripts/icon/render_kchr_icon.py install <вариант>  # AppIcon, AppIcon-Dark, AppIcon-Tinted
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "art-raw")
ICONSET = os.path.join(ROOT, "Deberc", "Assets.xcassets", "AppIcon.appiconset")
SERIF = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SYMBOLS = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"

S = 2048  # рисуем вдвое крупнее и уменьшаем до 1024 — ровные края

FELT_CENTER, FELT_MID, FELT_EDGE = (0x17, 0x66, 0x3D), (0x0F, 0x4A, 0x2B), (0x06, 0x30, 0x1B)
IVORY = (0xFF, 0xFD, 0xF7)
GOLD_FILL, GOLD_DEEP = (0xE3, 0xB2, 0x3C), (0xB0, 0x7F, 0x1F)
INK = {"spades": (0x14, 0x14, 0x14), "clubs": (0x14, 0x14, 0x14), "hearts": (0xCC, 0x12, 0x24),
       "diamonds": (0xCC, 0x12, 0x24)}
TINT = {"spades": (0xEC, 0xEE, 0xF2), "clubs": (0xEC, 0xEE, 0xF2), "hearts": (0xFB, 0xEA, 0xEA),
        "diamonds": (0xFB, 0xEA, 0xEA)}
SOFT = {"spades": (0x93, 0xA3, 0xBE), "clubs": (0x93, 0xA3, 0xBE), "hearts": (0xEE, 0x9A, 0xA3),
        "diamonds": (0xEE, 0x9A, 0xA3)}
GLYPH = {"spades": "♠", "clubs": "♣", "hearts": "♥", "diamonds": "♦"}
BACK = ((0x7E, 0x12, 0x22), (0x48, 0x08, 0x12))


def font(path, size):
    return ImageFont.truetype(path, max(1, int(size)))


def draw_centered(draw, text, center, size, path, fill):
    f = font(path, size)
    l, t, r, b = draw.textbbox((0, 0), text, font=f)
    draw.text((center[0] - (l + r) / 2, center[1] - (t + b) / 2), text, font=f, fill=fill)


class Metrics:
    """Как CardMetrics в приложении (обычный, не крупный индекс)."""

    def __init__(self, w):
        self.w, self.h = w, w * 1.45
        self.radius = w * 0.075
        self.rank_size, self.index_x, self.index_max = w * 0.31, w * 0.14, w * 0.21
        self.suit_size, rank_top = w * 0.185, w * 0.065
        self.rank_cy = rank_top + 0.35 * self.rank_size
        self.suit_cy = rank_top + 0.70 * self.rank_size + w * 0.012 + self.rank_size * 0.19 + self.suit_size / 2
        self.block_bottom = self.suit_cy + self.suit_size / 2
        self.block_right = self.index_x + max(self.index_max, self.suit_size) / 2
        self.margin = w * 0.065
        b1 = w * 0.04
        b2 = b1 + w * 0.016
        b3 = b2 + w * 0.05
        b4 = b3 + w * 0.014
        self.bands = [(0, b1, "ink"), (b1, b2, "gold"), (b2, b3, "soft"), (b3, b4, "gold")]

    def frame(self):
        w, h, fm = self.w, self.h, self.margin
        nx, ny = self.block_right + w * 0.04, self.block_bottom + w * 0.035
        return [(nx, fm), (w - fm, fm), (w - fm, h - ny), (w - nx, h - ny), (w - nx, h - fm),
                (fm, h - fm), (fm, ny), (nx, ny)]

    def portrait_rect(self):
        w = self.w
        left, right, top = self.block_right + w * 0.04, w - self.margin, self.margin
        bottom = self.h / 2 - self.bands[-1][1] + w * 0.03
        side = min(right - left, bottom - top)
        return ((left + right - side) / 2, bottom - side, side)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return m


def draw_index(img, m, rank, suit):
    d = ImageDraw.Draw(img)
    ink = INK[suit]
    draw_centered(d, rank, (m.index_x, m.rank_cy), m.rank_size * 1.0, SERIF, ink)
    draw_centered(d, GLYPH[suit], (m.index_x, m.suit_cy), m.suit_size * 1.25, SYMBOLS, ink)


def with_rotated_copy(img, fn):
    """Рисует fn на верхней половине и повторяет её, повернув на 180°."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fn(layer)
    img.alpha_composite(layer)
    img.alpha_composite(layer.rotate(180))


def court_card(w, rank, suit, portrait):
    m = Metrics(w)
    size = (int(m.w), int(m.h))
    card = Image.new("RGBA", size, IVORY + (255,))
    frame = m.frame()
    frame_mask = Image.new("L", size, 0)
    ImageDraw.Draw(frame_mask).polygon(frame, fill=255)
    inside = Image.new("RGBA", size, TINT[suit] + (255,))

    art = Image.open(os.path.join(RAW, portrait + ".png")).convert("RGBA")
    x, y, side = m.portrait_rect()
    art = art.resize((int(side), int(side)), Image.LANCZOS)
    half = Image.new("RGBA", size, (0, 0, 0, 0))
    half.alpha_composite(art, (int(x), int(y)))
    bands = ImageDraw.Draw(half)
    mid = m.h / 2
    colors = {"ink": INK[suit], "gold": GOLD_FILL, "soft": SOFT[suit]}
    for lo, hi, role in m.bands:
        bands.rectangle((m.margin - 1, mid - hi, m.w - m.margin + 1, mid - lo), fill=colors[role])
    top_only = Image.new("L", size, 0)
    ImageDraw.Draw(top_only).rectangle((0, 0, size[0], mid), fill=255)
    half.putalpha(ImageChops.multiply(half.getchannel("A"), top_only))
    inside.alpha_composite(half)
    inside.alpha_composite(half.rotate(180))
    card.paste(inside, (0, 0), frame_mask)

    d = ImageDraw.Draw(card)
    c = (m.w / 2, m.h / 2)
    r = w * 0.105
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=IVORY, outline=GOLD_DEEP, width=max(2, int(w * 0.016)))
    draw_centered(d, GLYPH[suit], c, r * 1.15 * 1.25, SYMBOLS, INK[suit])
    d.polygon(frame, outline=GOLD_DEEP, width=max(2, int(w * 0.016)))
    with_rotated_copy(card, lambda layer: draw_index(layer, m, rank, suit))
    card.putalpha(rounded_mask(size, int(m.radius)))
    return card


def nine_card(w, suit):
    m = Metrics(w)
    size = (int(m.w), int(m.h))
    card = Image.new("RGBA", size, IVORY + (255,))
    d = ImageDraw.Draw(card)
    top, bottom, col = m.h * 0.16, m.h * 0.84, w * 0.15
    layout = [(-1, 0), (-1, 1 / 3), (-1, 2 / 3), (-1, 1), (1, 0), (1, 1 / 3), (1, 2 / 3), (1, 1), (0, 0.5)]
    for column, t in layout:
        cx, cy = m.w / 2 + column * col, top + t * (bottom - top)
        pip = Image.new("RGBA", (int(w * 0.3), int(w * 0.3)), (0, 0, 0, 0))
        draw_centered(ImageDraw.Draw(pip), GLYPH[suit], (pip.width / 2, pip.height / 2), w * 0.16 * 1.25,
                      SYMBOLS, INK[suit])
        if cy > m.h / 2 + 0.5:
            pip = pip.rotate(180)
        card.alpha_composite(pip, (int(cx - pip.width / 2), int(cy - pip.height / 2)))
    with_rotated_copy(card, lambda layer: draw_index(layer, m, "9", suit))
    card.putalpha(rounded_mask(size, int(m.radius)))
    return card


def back_card(w):
    m = Metrics(w)
    size = (int(m.w), int(m.h))
    card = Image.new("RGBA", size, IVORY + (255,))
    margin = w * 0.055
    field = (int(margin), int(margin), int(m.w - margin), int(m.h - margin))
    fw, fh = field[2] - field[0], field[3] - field[1]
    grad = Image.new("RGBA", (fw, fh))
    gd = ImageDraw.Draw(grad)
    for i in range(fw + fh):
        t = i / (fw + fh)
        col = tuple(int(BACK[0][k] + (BACK[1][k] - BACK[0][k]) * t) for k in range(3)) + (255,)
        gd.line((i, 0, i - fh, fh), fill=col, width=2)
    ornament = Image.open(os.path.join(RAW, "back-ornament.png")).convert("RGBA").resize((fw, fh), Image.LANCZOS)
    grad.alpha_composite(ornament)
    card.paste(grad, field[:2], rounded_mask((fw, fh), int(m.radius * 0.6)))
    d = ImageDraw.Draw(card)
    c = (m.w / 2, m.h / 2)
    ew, eh = w * 0.26, w * 0.44
    d.ellipse((c[0] - ew / 2, c[1] - eh / 2, c[0] + ew / 2, c[1] + eh / 2), fill=BACK[1])
    d.ellipse((c[0] - ew / 2 + w * 0.03, c[1] - eh / 2 + w * 0.03, c[0] + ew / 2 - w * 0.03, c[1] + eh / 2 - w * 0.03),
              outline=GOLD_FILL, width=max(2, int(w * 0.006)))
    draw_centered(d, "Д", c, w * 0.22, SERIF, GOLD_FILL)
    card.putalpha(rounded_mask(size, int(m.radius)))
    return card


def felt(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c = size / 2
    rmax = math.hypot(c, c)
    for y in range(size):
        for x in range(size):
            t = math.hypot(x - c, y - c * 0.9) / rmax
            a, b, u = (FELT_CENTER, FELT_MID, t / 0.55) if t < 0.55 else (FELT_MID, FELT_EDGE, (t - 0.55) / 0.45)
            u = min(1.0, u)
            px[x, y] = tuple(int(a[k] + (b[k] - a[k]) * u) for k in range(3))
    noise = Image.effect_noise((size, size), 18).convert("RGB")
    return Image.blend(img, ImageChops.overlay(img, noise), 0.10).convert("RGBA")


def place(canvas, card, center, angle, shadow=True):
    rotated = card.rotate(-angle, resample=Image.BICUBIC, expand=True)
    pos = (int(center[0] - rotated.width / 2), int(center[1] - rotated.height / 2))
    if shadow:
        sh = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
        sh.putalpha(rotated.getchannel("A").point(lambda v: int(v * 0.55)))
        sh = sh.filter(ImageFilter.GaussianBlur(S * 0.02))
        canvas.alpha_composite(sh, (pos[0], pos[1] + int(S * 0.02)))
    canvas.alpha_composite(rotated, pos)


VARIANTS = {
    # Валет пик (карачаевский джигит) на фоне рубашки с орнаментом.
    "jack-back": lambda: [("back", -13, (0.40, 0.49)), ("court", 7, (0.58, 0.52), "В", "spades", "court-jack-spades")],
    # Два народа: атаман (король червей) и карачаевский джигит (валет пик).
    "ataman-jack": lambda: [("court", -12, (0.39, 0.49), "К", "hearts", "court-king-hearts"),
                            ("court", 8, (0.60, 0.52), "В", "spades", "court-jack-spades")],
    # Джас и менель: девятка и валет — старшие козыри деберца.
    "nine-jack": lambda: [("nine", -13, (0.40, 0.49), "spades"),
                          ("court", 7, (0.58, 0.52), "В", "spades", "court-jack-spades")],
    # Старейшина: одна крупная карта — король пик.
    "elder": lambda: [("court", 5, (0.50, 0.51), "К", "spades", "court-king-spades", 0.56)],
}


def compose(name, background=True):
    canvas = felt(S) if background else Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for item in VARIANTS[name]():
        kind, angle, (cx, cy) = item[0], item[1], item[2]
        if kind == "back":
            card = back_card(S * 0.46)
        elif kind == "nine":
            card = nine_card(S * 0.46, item[3])
        else:
            width = item[6] if len(item) > 6 else 0.46
            card = court_card(S * width, item[3], item[4], item[5])
        place(canvas, card, (S * cx, S * cy), angle)
    return canvas.resize((1024, 1024), Image.LANCZOS)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "preview"
    if cmd == "preview":
        out = sys.argv[2] if len(sys.argv) > 2 else "."
        os.makedirs(out, exist_ok=True)
        for name in VARIANTS:
            compose(name).convert("RGB").save(os.path.join(out, "icon-%s.png" % name))
            print("icon-%s.png" % name)
    elif cmd == "install":
        name = sys.argv[2]
        compose(name).convert("RGB").save(os.path.join(ICONSET, "AppIcon.png"))  # без альфа-канала
        dark = compose(name, background=False)
        dark = Image.merge("RGBA", [c.point(lambda v: int(v * 0.88)) for c in dark.split()[:3]] + [dark.getchannel("A")])
        dark.save(os.path.join(ICONSET, "AppIcon-Dark.png"))
        gray = compose(name, background=False)
        tinted = Image.new("RGB", (1024, 1024), (0, 0, 0))
        tinted.paste(gray.convert("L").convert("RGB"), (0, 0), gray.getchannel("A"))
        tinted.save(os.path.join(ICONSET, "AppIcon-Tinted.png"))
        print("installed", name)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
