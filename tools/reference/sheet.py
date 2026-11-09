"""Side-by-side sheet: each mood-study reference frame beside the Studio capture of the same shot.

    python tools/reference/sheet.py OUT.jpg TITLE ref1.png:port1.jpg:label1 ref2.png:port2.jpg:label2 ...

Both frames are scaled to one row height; Studio's viewport is narrower than the reference's 16:9, so its frame is
the narrower one. Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

ROW = 300
GAP = 8
LABEL = 26


def font(size):
    for name in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def fit(path):
    im = Image.open(path).convert("RGB")
    return im.resize((round(im.width * ROW / im.height), ROW), Image.LANCZOS)


def main():
    out, title, rows = sys.argv[1], sys.argv[2], [a.split(":", 2) for a in sys.argv[3:]]
    pairs = [(fit(r), fit(p), label) for r, p, label in rows]
    width = max(a.width + b.width for a, b, _ in pairs) + GAP * 3
    height = LABEL + GAP + len(pairs) * (ROW + LABEL + GAP)
    sheet = Image.new("RGB", (width, height), (24, 26, 30))
    draw = ImageDraw.Draw(sheet)
    f, small = font(18), font(14)
    draw.text((GAP, 4), title, fill=(235, 235, 235), font=f)
    y = LABEL + GAP
    for ref, port, label in pairs:
        draw.text((GAP, y + 4), f"{label}   ·   left: mood study   ·   right: Studio", fill=(190, 190, 190), font=small)
        y += LABEL
        sheet.paste(ref, (GAP, y))
        sheet.paste(port, (GAP * 2 + ref.width, y))
        y += ROW + GAP
    sheet.save(out, quality=88)


if __name__ == "__main__":
    main()
