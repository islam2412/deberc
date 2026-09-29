#!/usr/bin/env python3
"""Оформляет скриншоты для App Store: сукно, подпись сверху, скриншот со скруглёнными углами.

    python3 scripts/frame-shots.py --out build/appstore/iphone \\
        build/appstore/raw/iphone table-p2-s3-07-playing.png table-p3-s7-12-playing.png …

Кадры (имена в папке сырых снимков или пути) идут в том же порядке, что подписи
в docs/appstore/ru/captions.txt: первый кадр — первая строка и т. д. На выходе —
01-<кадр>.png, 02-<кадр>.png… строго 1320×2868 (iPhone 6,9″) или 2064×2752 (iPad 13″),
без прозрачности. Устройство определяется по пропорциям снимков (или --device).
Сырые снимки снимает scripts/appstore-shots.sh.

Скрипт отказывается работать, если кадров больше 10 (предел App Store) или больше, чем подписей,
и если снимок не того размера: не портретный, не той пропорции или слишком мелкий.
Нужен Pillow: pip install pillow (или pip install -r scripts/requirements.txt).
"""

import argparse
import glob
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CAPTIONS = os.path.join(ROOT, "docs", "appstore", "ru", "captions.txt")

# Размеры App Store Connect и допустимые пропорции сырых снимков (ширина / высота).
DEVICES = {
    "iphone": {"size": (1320, 2868), "aspect": (0.44, 0.50), "corner": 0.115},
    "ipad": {"size": (2064, 2752), "aspect": (0.66, 0.78), "corner": 0.035},
}
MAX_FRAMES = 10

# Цвета темы (Deberc/Views/Theme.swift).
FELT_CENTER, FELT_MID, FELT_EDGE = (0x17, 0x66, 0x3D), (0x0F, 0x4A, 0x2B), (0x06, 0x30, 0x1B)
IVORY = (0xFF, 0xF8, 0xEC)       # tableText
GOLD = (0xE3, 0xB2, 0x3C)        # goldFill
GOLD_LIGHT = (0xFF, 0xE0, 0x8A)  # goldLight

# Системный жирный шрифт с кириллицей: SF Pro (переменный) или Arial Bold.
FONTS = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

# Доли высоты холста.
SHOT_HEIGHT = 0.79    # скриншот
BOTTOM_MARGIN = 0.03  # поле под скриншотом
SHOT_MAX_WIDTH = 0.88  # доля ширины холста


def fail(message):
    sys.exit("frame-shots: " + message)


def load_font(size):
    for path in FONTS:
        if not os.path.exists(path):
            continue
        font = ImageFont.truetype(path, size)
        try:
            # SF Pro: жирный, «дисплейный» оптический размер для крупного текста.
            axes = {a["name"]: a for a in font.get_variation_axes()}
            values = []
            for name, axis in axes.items():
                want = {b"Weight": 700, b"Optical Size": axis["maximum"]}.get(name, axis["default"])
                values.append(max(axis["minimum"], min(axis["maximum"], want)))
            font.set_variation_by_axes(values)
        except (OSError, AttributeError):
            pass  # обычный (не переменный) шрифт
        return font
    fail("не найден жирный шрифт с кириллицей (%s)" % ", ".join(FONTS))


def read_captions(path):
    with open(path, encoding="utf-8") as f:
        lines = [line.strip() for line in f]
    return [line for line in lines if line and not line.startswith("#")]


def felt(size):
    """Сукно: мягкий радиальный градиент цветов стола и едва заметная ворсинка."""
    w, h = size
    # Градиент гладкий — считаем его в 1/8 размера и растягиваем.
    sw, sh = w // 8, h // 8
    small = Image.new("RGB", (sw, sh))
    px = small.load()
    for y in range(sh):
        for x in range(sw):
            # Светлее всего — за верхней частью скриншота, к углам темнеет.
            t = min(1.0, math.hypot((x - sw * 0.5) / (sw * 0.95), (y - sh * 0.42) / (sh * 0.62)))
            a, b, u = (FELT_CENTER, FELT_MID, t / 0.55) if t < 0.55 else (FELT_MID, FELT_EDGE, (t - 0.55) / 0.45)
            px[x, y] = tuple(int(a[k] + (b[k] - a[k]) * min(1.0, u) + 0.5) for k in range(3))
    image = small.resize(size, Image.BICUBIC)
    noise = Image.effect_noise(size, 2.2).convert("RGB")
    return ImageChops.add(image, noise, offset=-128)


def rounded_mask(size, radius, outline=0, ss=4):
    """Маска скруглённого прямоугольника (или его кромки толщиной outline) с гладкими краями:
    рисуем вчетверо крупнее и уменьшаем."""
    w, h = size[0] * ss, size[1] * ss
    mask = Image.new("L", (w, h), 0)
    box = (0, 0, w - 1, h - 1)
    if outline:
        ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius * ss, outline=255, width=outline * ss)
    else:
        ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius * ss, fill=255)
    return mask.resize(size, Image.LANCZOS)


# Предлоги и союзы, которыми не заканчивают строку («Деберц по / нашим правилам»).
CLINGING = {"а", "без", "в", "во", "для", "до", "за", "и", "из", "или", "как", "к", "ко", "на", "не", "но",
            "о", "об", "от", "по", "с", "со", "у"}


def wrap(text, font, max_width, draw, lines=2):
    """Одна строка или (если можно) две, разбитые как можно ровнее."""
    if draw.textlength(text, font=font) <= max_width:
        return [text]
    if lines < 2:
        return None
    words = text.split()
    best = None
    for i in range(1, len(words)):
        # Тире не оставляем в начале второй строки, предлог — в конце первой.
        if words[i] in ("—", "–") or words[i - 1].lower() in CLINGING:
            continue
        pair = [" ".join(words[:i]), " ".join(words[i:])]
        widest = max(draw.textlength(line, font=font) for line in pair)
        # Одно слово во второй строке смотрится обрывком: «Деберц по нашим / правилам».
        cost = widest * (1.2 if i == len(words) - 1 else 1.0)
        if widest <= max_width and (best is None or cost < best[0]):
            best = (cost, pair)
    return best[1] if best else None


def caption_font(captions, width, height_limit, base, one_line_min):
    """Кегль, общий для всех кадров, и число строк: по возможности все подписи в одну строку
    не мельче one_line_min, иначе — самый крупный кегль, при котором они умещаются в две."""
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    for lines in (1, 2):
        size = base
        while size >= (one_line_min if lines == 1 else 24):
            font = load_font(size)
            layouts = [wrap(c, font, width, probe, lines) for c in captions]
            if all(layouts) and max(len(l) for l in layouts) * size * 1.18 <= height_limit:
                return font, size, lines
            size -= 2
    fail("подписи не помещаются даже мелким шрифтом")


def ornament(draw, center, width, scale):
    """Золотой акцент под подписью: две тонкие линии и ромб между ними."""
    cx, cy = center
    r = 16 * scale
    gap = r * 2.0
    line = max(2, int(round(3.5 * scale)))
    for sign in (-1, 1):
        x0, x1 = cx + sign * gap, cx + sign * (width / 2)
        draw.line((min(x0, x1), cy, max(x0, x1), cy), fill=GOLD, width=line)
        # Точка на конце линии.
        d = 5 * scale
        draw.ellipse((x1 - d, cy - d, x1 + d, cy + d), fill=GOLD)
    draw.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=GOLD_LIGHT, outline=GOLD)


def frame(shot, caption_lines, font, font_size, device):
    spec = DEVICES[device]
    W, H = spec["size"]
    canvas = felt((W, H))

    # Скриншот: ≈79 % высоты, по центру, у нижнего края.
    aspect = shot.width / shot.height
    sh = int(H * SHOT_HEIGHT)
    sw = int(sh * aspect)
    if sw > W * SHOT_MAX_WIDTH:
        sw = int(W * SHOT_MAX_WIDTH)
        sh = int(sw / aspect)
    x = (W - sw) // 2
    y = H - int(H * BOTTOM_MARGIN) - sh
    radius = int(sw * spec["corner"])
    image = shot.convert("RGB").resize((sw, sh), Image.LANCZOS)
    mask = rounded_mask((sw, sh), radius)

    # Мягкая тень: размытая на холсте с запасом, чуть ниже скриншота.
    pad = int(W * 0.08)
    shadow = Image.new("L", (sw + 2 * pad, sh + 2 * pad), 0)
    shadow.paste(mask.point(lambda v: int(v * 0.75)), (pad, pad))
    shadow = shadow.filter(ImageFilter.GaussianBlur(W * 0.022))
    dark = Image.new("RGB", shadow.size, (0, 0x0C, 0x05))
    canvas.paste(dark, (x - pad, y - pad + int(H * 0.008)), shadow)
    canvas.paste(image, (x, y), mask)

    # Тонкая золотая кромка, чтобы зелёный стол на снимке не сливался с сукном вокруг.
    edge = rounded_mask((sw, sh), radius, outline=max(2, W // 600))
    canvas.paste(Image.new("RGB", (sw, sh), GOLD), (x, y), edge.point(lambda v: int(v * 0.55)))

    # Подпись и золотой акцент — по центру поля над скриншотом.
    draw = ImageDraw.Draw(canvas)
    scale = W / 1320
    line_h = font_size * 1.18
    ornament_gap, ornament_h = font_size * 0.40, 32 * scale
    block = len(caption_lines) * line_h + ornament_gap + ornament_h
    top = (y - block) / 2 + font_size * 0.04
    for i, line in enumerate(caption_lines):
        cy = top + i * line_h + line_h / 2
        draw.text((W / 2, cy), line, font=font, fill=IVORY, anchor="mm")
    oy = top + len(caption_lines) * line_h + ornament_gap + ornament_h / 2
    ornament(draw, (W / 2, oy), min(W * 0.42, 560 * scale), scale)
    return canvas


def island_visible(shot):
    """Чёрная «таблетка» острова: симулятор iPhone иногда рисует её на снимке."""
    gray = shot.convert("L")
    y = int(shot.height * 0.031)
    xs = [int(shot.width * (0.5 + dx)) for dx in (-0.08, -0.04, 0, 0.04, 0.08)]
    return all(gray.getpixel((x, y)) < 10 for x in xs)


def detect(shot):
    aspect = shot.width / shot.height
    for name, spec in DEVICES.items():
        lo, hi = spec["aspect"]
        if lo <= aspect <= hi:
            return name
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raw", help="папка сырых PNG (build/appstore/raw/<имя>)")
    parser.add_argument("frames", nargs="+", help="кадры по порядку подписей: имя файла в папке или путь")
    parser.add_argument("--out", required=True, help="куда сложить 01-….png, 02-….png…")
    parser.add_argument("--captions", default=CAPTIONS, help="файл подписей, по одной на строку")
    parser.add_argument("--device", choices=["auto"] + sorted(DEVICES), default="auto")
    args = parser.parse_args()

    if len(args.frames) > MAX_FRAMES:
        fail("кадров %d, App Store принимает не больше %d" % (len(args.frames), MAX_FRAMES))
    captions = read_captions(args.captions)
    if len(args.frames) > len(captions):
        fail("кадров %d, а подписей в %s только %d" % (len(args.frames), args.captions, len(captions)))

    shots = []
    for name in args.frames:
        path = name if os.path.exists(name) else os.path.join(args.raw, name)
        if not os.path.exists(path):
            fail("нет файла %s" % path)
        with Image.open(path) as image:
            shots.append((path, image.copy()))

    devices = set()
    for path, shot in shots:
        kind = detect(shot)
        if shot.width >= shot.height or kind is None:
            fail("%s: размер %d×%d — не портретный скриншот iPhone или iPad"
                 % (os.path.basename(path), shot.width, shot.height))
        devices.add(kind)
    device = args.device if args.device != "auto" else None
    if device is None:
        if len(devices) > 1:
            fail("в одном наборе снимки и iPhone, и iPad — оформляйте их отдельно")
        device = devices.pop()
    W, H = DEVICES[device]["size"]
    need = int(H * SHOT_HEIGHT * 0.8)
    for path, shot in shots:
        if detect(shot) != device:
            fail("%s: пропорции не как у %s" % (os.path.basename(path), device))
        if shot.height < need:
            fail("%s: высота %d px — мелко для %d×%d, нужен снимок с симулятора в полном размере"
                 % (os.path.basename(path), shot.height, W, H))

    for path, shot in shots:
        if device == "iphone" and island_visible(shot):
            print("внимание: на %s виден чёрный остров — лучше взять соседний кадр" % os.path.basename(path),
                  file=sys.stderr)

    # Кегль общий для всех кадров: подписи одного размера на всей странице App Store.
    scale = W / 1320
    text_width = W * (0.88 if device == "iphone" else 0.80)
    free = H * (1 - SHOT_HEIGHT - BOTTOM_MARGIN) * 0.72
    # На iPad подписи встают в одну строку, на iPhone — в две.
    base, one_line_min = (int(118 * scale), 10_000) if device == "iphone" else (124, 96)
    font, size, lines = caption_font(captions, text_width, free, base, one_line_min)

    os.makedirs(args.out, exist_ok=True)
    for old in glob.glob(os.path.join(args.out, "[0-9][0-9]-*.png")):
        os.remove(old)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    for i, ((path, shot), caption) in enumerate(zip(shots, captions), start=1):
        image = frame(shot, wrap(caption, font, text_width, probe, lines), font, size, device)
        assert image.size == (W, H) and image.mode == "RGB"
        stem = os.path.splitext(os.path.basename(path))[0]
        dest = os.path.join(args.out, "%02d-%s.png" % (i, stem))
        image.save(dest, optimize=True)
        print("%s  %d×%d  «%s»" % (dest, W, H, caption))


if __name__ == "__main__":
    main()
