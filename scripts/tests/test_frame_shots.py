"""Тесты оформления скриншотов (scripts/frame-shots.py): переносы подписей, размеры, отказы."""

import importlib.util
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO

try:
    from PIL import Image, ImageDraw
    HAVE_PIL = True
except ImportError:  # pragma: no cover
    HAVE_PIL = False

HERE = os.path.dirname(__file__)


def load():
    spec = importlib.util.spec_from_file_location("frame_shots", os.path.join(HERE, "..", "frame-shots.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Подписи рисуются системным шрифтом: на машине без него (другой образ CI) такие тесты
# пропускаются, а не падают. Отказы по числу и размеру кадров шрифта не требуют.
HAVE_FONT = HAVE_PIL and any(os.path.exists(path) for path in load().FONTS)


@unittest.skipUnless(HAVE_PIL, "нужен Pillow")
@unittest.skipUnless(HAVE_FONT, "нет жирного шрифта с кириллицей из FONTS")
class WrapTest(unittest.TestCase):
    def setUp(self):
        self.fs = load()
        self.font = self.fs.load_font(100)
        self.draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    def width(self, text):
        return self.draw.textlength(text, font=self.font)

    def wrap(self, text, max_width, lines=2):
        return self.fs.wrap(text, self.font, max_width, self.draw, lines)

    def test_short_caption_stays_on_one_line(self):
        self.assertEqual(self.wrap("Совет и отмена хода", 10_000), ["Совет и отмена хода"])

    def test_one_line_mode_refuses_to_wrap(self):
        self.assertIsNone(self.wrap("Совет и отмена хода", self.width("Совет и отмена"), lines=1))

    def test_no_preposition_at_line_end_and_no_single_word_tail(self):
        text = "Деберц по нашим правилам"
        self.assertEqual(self.wrap(text, self.width("по нашим правилам") + 1), ["Деберц", "по нашим правилам"])

    def test_dash_stays_on_first_line(self):
        text = "Крупные карты — удобно читать"
        self.assertEqual(self.wrap(text, self.width("Крупные карты —") + 1), ["Крупные карты —", "удобно читать"])

    def test_too_narrow(self):
        self.assertIsNone(self.wrap("Без интернета и рекламы", self.width("и")))


@unittest.skipUnless(HAVE_PIL, "нужен Pillow")
class FrameTest(unittest.TestCase):
    def setUp(self):
        self.fs = load()
        self.tmp = tempfile.TemporaryDirectory()
        self.raw = os.path.join(self.tmp.name, "raw")
        self.out = os.path.join(self.tmp.name, "out")
        os.makedirs(self.raw)

    def tearDown(self):
        self.tmp.cleanup()

    def shot(self, name, size):
        Image.new("RGB", size, (0x0F, 0x4A, 0x2B)).save(os.path.join(self.raw, name))
        return name

    def run_script(self, *frames):
        argv = sys.argv
        sys.argv = ["frame-shots.py", "--out", self.out, self.raw] + list(frames)
        try:
            with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
                self.fs.main()
        finally:
            sys.argv = argv

    @unittest.skipUnless(HAVE_FONT, "нет жирного шрифта с кириллицей из FONTS")
    def test_iphone_and_ipad_sizes(self):
        for kind, raw_size, want in (("iphone", (1320, 2868), (1320, 2868)),
                                     ("ipad", (2064, 2752), (2064, 2752)),
                                     ("ipad-11", (1640, 2360), (2064, 2752))):
            with self.subTest(kind):
                self.run_script(self.shot(kind + "-a.png", raw_size), self.shot(kind + "-b.png", raw_size))
                files = sorted(os.listdir(self.out))
                self.assertEqual(files, ["01-%s-a.png" % kind, "02-%s-b.png" % kind])
                for name in files:
                    with Image.open(os.path.join(self.out, name)) as image:
                        self.assertEqual((image.size, image.mode), (want, "RGB"))

    def test_refuses_more_than_ten_frames(self):
        name = self.shot("a.png", (1320, 2868))
        with self.assertRaises(SystemExit) as err:
            self.run_script(*[name] * 11)
        self.assertIn("не больше 10", str(err.exception))

    def test_refuses_more_frames_than_captions(self):
        name = self.shot("a.png", (1320, 2868))
        with self.assertRaises(SystemExit) as err:
            self.run_script(*[name] * 7)
        self.assertIn("подписей", str(err.exception))

    def test_refuses_wrong_size(self):
        for name, size in (("landscape.png", (2752, 2064)), ("square.png", (1000, 1000)), ("small.png", (400, 870))):
            with self.subTest(name), self.assertRaises(SystemExit):
                self.run_script(self.shot(name, size))

    def test_refuses_mixed_devices(self):
        with self.assertRaises(SystemExit) as err:
            self.run_script(self.shot("phone.png", (1320, 2868)), self.shot("pad.png", (2064, 2752)))
        self.assertIn("iPhone, и iPad", str(err.exception))


if __name__ == "__main__":
    unittest.main()
