#!/usr/bin/env python3
"""Готовит иллюстрации из Higgsfield для каталога ресурсов (подробности — docs/ART.md).

art-raw/<имя>.png  ->  Deberc/Assets.xcassets/Art/<имя>.imageset/<имя>.png (+ Contents.json)

Размеры: court-* 512×512, avatar-* 256×256, back-ornament 640×960.
Прозрачность «подтягивается» (почти непрозрачное -> 255, почти прозрачное -> 0),
орнамент рубашки делается строго симметричным (зеркально слева направо и поворотом на 180°),
всё сжимается в палитру на 256 цветов с прозрачностью.

    pip install Pillow
    python3 scripts/prepare_art.py              # все файлы из art-raw/
    python3 scripts/prepare_art.py court-king-spades avatar-sasha
"""
import json
import os
import sys

from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "art-raw")
CATALOG = os.path.join(HERE, "..", "Deberc", "Assets.xcassets", "Art")


def target_size(name):
    if name.startswith("court-"):
        return (512, 512)
    if name.startswith("avatar-"):
        return (256, 256)
    if name == "back-ornament":
        return (640, 960)
    raise ValueError("неизвестный вид картинки: " + name)


def snap_alpha(im):
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v >= 245 else (0 if v <= 4 else v))
    return Image.merge("RGBA", (r, g, b, a))


def symmetrize(im):
    """Левая половина отражается вправо, верхняя поворачивается на 180° вниз."""
    w, h = im.size
    left = im.crop((0, 0, w // 2, h))
    lr = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lr.paste(left, (0, 0))
    lr.paste(ImageOps.mirror(left), (w - w // 2, 0))
    top = lr.crop((0, 0, w, h // 2))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(top, (0, 0))
    out.paste(top.rotate(180), (0, h - h // 2))
    return out


def write_json(path, payload):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
        f.write("\n")


def process(name):
    src = os.path.join(RAW, name + ".png")
    im = snap_alpha(Image.open(src).convert("RGBA"))
    if name == "back-ornament":
        im = symmetrize(im)
    size = target_size(name)
    if im.size != size:
        # Та же пропорция — просто уменьшаем; иначе вписываем по центру (фигуры — низом к низу).
        scale = min(size[0] / im.width, size[1] / im.height)
        resized = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        x = (size[0] - resized.width) // 2
        y = size[1] - resized.height if name.startswith("court-") else (size[1] - resized.height) // 2
        canvas.alpha_composite(resized, (x, y))
        im = canvas
    folder = os.path.join(CATALOG, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    out = os.path.join(folder, name + ".png")
    # Палитра на 256 цветов: в размере карты разницы не видно, файл в 4 раза меньше.
    im = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    im.save(out, optimize=True)
    write_json(os.path.join(folder, "Contents.json"), {
        "images": [{"filename": name + ".png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })
    print("%-24s -> %s, %d КБ" % (name, size, os.path.getsize(out) // 1024))


def main(names):
    os.makedirs(CATALOG, exist_ok=True)
    write_json(os.path.join(CATALOG, "Contents.json"), {"info": {"author": "xcode", "version": 1}})
    names = names or sorted(f[:-4] for f in os.listdir(RAW) if f.endswith(".png"))
    for name in names:
        process(name)


if __name__ == "__main__":
    main(sys.argv[1:])
