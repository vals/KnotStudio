#!/usr/bin/env python3
"""Render several knot-render invocations into one labelled contact sheet.

  python3 Tools/contact_sheet.py out.png COLUMNS "label|notation|key=value ..." ...
"""
import subprocess, sys, tempfile, os
from PIL import Image, ImageDraw

def main():
    out, columns, specs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    subprocess.run(["zsh", os.path.join(root, "Scripts/render.sh")], check=True)
    tiles = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, spec in enumerate(specs):
            label, notation, *rest = spec.split("|")
            options = rest[0].split() if rest else []
            if not any(o.startswith("size=") for o in options):
                options.append("size=520")
            path = os.path.join(tmp, f"{i}.png")
            subprocess.run([os.path.join(root, ".build/knot-render"), path, notation, *options],
                           check=True, stdout=subprocess.DEVNULL)
            tile = Image.open(path).convert("RGB")
            ImageDraw.Draw(tile).text((10, 8), label, fill=(255, 255, 255))
            tiles.append(tile)
    w, h = tiles[0].size
    rows = (len(tiles) + columns - 1) // columns
    sheet = Image.new("RGB", (w * columns, h * rows), (19, 24, 31))
    for i, tile in enumerate(tiles):
        sheet.paste(tile, ((i % columns) * w, (i // columns) * h))
    sheet.save(out)

if __name__ == "__main__":
    main()
