#!/usr/bin/env python3
"""Собирает docs/preview.png для README из скриншотов симулятора.

    python3 scripts/make-preview.py --out docs/preview.png \\
        "Меню=shots/iphone-big-screen-menu.png" "Торговля=shots/iphone-big-screen-table.png" \\
        "Розыгрыш=shots/iphone-big-auto2p-03.png" "Итоги сдачи=shots/iphone-big-screen-summary.png"

Скриншоты — из артефакта workflow «Скриншоты» (полные PNG) или CI (JPEG).
Нужен Pillow: pip install pillow.
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

BACKGROUND = (22, 38, 28)
CAPTION = (250, 204, 77)  # золото, как Theme.gold

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/SFNS.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(path, size):
    for candidate in ([path] if path else []) + FONT_CANDIDATES:
        if candidate and os.path.exists(candidate):
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def parse_item(text):
    if "=" not in text:
        raise argparse.ArgumentTypeError("ожидается «Подпись=путь к скриншоту»: %s" % text)
    caption, path = text.split("=", 1)
    if not os.path.exists(path):
        raise argparse.ArgumentTypeError("нет файла %s" % path)
    return caption.strip(), path


def compose(items, column_width=390, gap=24, caption_height=70, bottom=24, font=None, radius=0):
    shots = []
    for caption, path in items:
        image = Image.open(path).convert("RGB")
        height = round(image.height * column_width / image.width)
        shots.append((caption, image.resize((column_width, height), Image.LANCZOS)))
    tallest = max(s.height for _, s in shots)
    width = gap + len(shots) * (column_width + gap)
    canvas = Image.new("RGB", (width, caption_height + tallest + bottom), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    for i, (caption, shot) in enumerate(shots):
        x = gap + i * (column_width + gap)
        if radius:
            mask = Image.new("L", shot.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius, fill=255)
            canvas.paste(shot, (x, caption_height), mask)
        else:
            canvas.paste(shot, (x, caption_height))
        box = draw.textbbox((0, 0), caption, font=font)
        tx = x + (column_width - (box[2] - box[0])) // 2 - box[0]
        ty = (caption_height - (box[3] - box[1])) // 2 - box[1]
        draw.text((tx, ty), caption, fill=CAPTION, font=font)
    return canvas


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("items", nargs="+", type=parse_item, help="«Подпись=путь»")
    p.add_argument("--out", default="docs/preview.png")
    p.add_argument("--column-width", type=int, default=390)
    p.add_argument("--font", help="путь к шрифту TTF для подписей")
    p.add_argument("--font-size", type=int, default=34)
    p.add_argument("--radius", type=int, default=0, help="скругление углов скриншотов, px")
    args = p.parse_args(argv)
    image = compose(args.items, column_width=args.column_width,
                    font=load_font(args.font, args.font_size), radius=args.radius)
    image.save(args.out, optimize=True)
    print("Готово: %s (%d×%d)" % (args.out, image.width, image.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
