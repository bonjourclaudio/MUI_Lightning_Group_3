#!/usr/bin/env python3
# Author: MUI group 3
"""
Bakes the laser-cut landscape (vertical profile slices) into a height grid for the app.

Input : the cutting SVGs, read at 96 units per inch like the laser cutter did (checked
        against the real model: 409 mm wide), red outlines = slices,
        blue numbers = slice index (01 … N). Pieces may be rotated on the sheet.
Output: ../MUI_Lightning_Group_3/Resources/terrain_slices.json
        { "widthMM", "stepMM", "slices": [[height_mm, …], …] }  – slice 01 first,
        heights above the table (bottom edge of the slice), sampled from the label side.

The slice spacing (material thickness + gaps) is NOT in the files – set it in the app:
Layout.slicePitch.

    pip install svgpathtools numpy pillow
    python3 Tools/bake_terrain.py path/to/svg_folder
"""
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from svgpathtools import parse_path
from xml.etree import ElementTree as ET

SRC = sys.argv[1] if len(sys.argv) > 1 else "svg"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "MUI_Lightning_Group_3", "Resources", "terrain_slices.json")
PT_PER_MM = 96 / 25.4      # the cutter treated the SVG units as 96 dpi pixels
STEP_MM = 1.5
NS = "{http://www.w3.org/2000/svg}"
GW, GH = 12, 18
# Digit shapes (12×18 rasters) of the Illustrator number font, for reading the slice numbers.
TEMPLATES = {
    "0": "000001100000001111111000011011101100011111111110111100001010101100001010101000001011101000001111101000001111101000001111101000001111101000001111101000001010111100011010010111110110011011111100001111111000000011100000",
    "1": "000000000000000000000000000000010000000000111000000000101000000111101000001110001000001111101000000111101000000000101000000000101000000000101000000000101000000000101000000000101000000000101000000000101000000000101000",
    "2": "000001110000001111111100011101110110011111111011010100001101111100000101111100000101011000001101000000011011000001111110000111011100001111110000011011000000010110000000111111111111100111111111111111111111111111111111",
    "3": "000011110000001111111100011011110110010111111010111100001010111100001010011000011110000011111110000011101110000011111110000000011111111000001101111000001101101100001111110111111010011111110110001111111100000011100000",
    "4": "000001111000000011011000000111111000000111111000001111111000011111111000111101111000111001111000111001111000011111101110011111000110111111101110000001111000000001111000000001111000000000111000000000000000000000000000",
    "5": "001111111111001011111111001111111110011110000000011100000000011111111000011111101110010111111011011110001111001000000101000000000101011000000101111100001101110110011111011011111110001111111100000011110000000000000000",
    "6": "000001000000001111111000011111111100010111111110111100011110101000001110101011110000111111111100101111110110101110011110101000001010101000001010101000001010101000001010111110011110011111111100001111111000000111110000",
    "7": "000000000000000000000000111111111110111111111111100000000011111111111110000000011110000000111100000001111000000001111000000011110000000010100000000110100000000101100000001101000000001111000000001010000000001010000000",
    "8": "000000000000000111111000001111101110011111111010010100001010110100001011010110011010011111111110001101101100011111111110111110011011111100001101101100001101101100001111110110011111011111111110001111111100000111111000",
    "9": "000011111000001110101110011011111110010110001111010100001101110100000101110100000101010100001101011111111101001111111101000111111101000001100101011100001111010110001010011111111110001101111100000111111000000000000000"
}
TEMPLATES = {k: np.array([int(c) for c in v], np.uint8).reshape(GH, GW) for k, v in TEMPLATES.items()}

def glyph_points(path, n=8):
    return [[seg.point(t) for t in np.linspace(0, 1, n)] for seg in path]

def orientation(glyphs):
    c = [np.mean([[z.real, z.imag] for seg in g for z in seg], axis=0) for g in glyphs]
    d = c[-1] - c[0]
    if abs(d[0]) > abs(d[1]):
        return 0 if d[0] > 0 else 180
    return 90 if d[1] > 0 else 270

def rot_matrix(deg):
    th = -np.radians(deg)
    return np.array([[np.cos(th), -np.sin(th)], [np.sin(th), np.cos(th)]])

def raster(g, rot):
    pts = np.array([[z.real, z.imag] for seg in g for z in seg])
    R = rot_matrix(rot)
    q = (pts - pts.mean(0)) @ R.T
    scale = max(q.max(0) - q.min(0)) / (GH - 2)
    im = Image.new("L", (GW * 4, GH * 4), 0)
    d = ImageDraw.Draw(im)
    for seg in g:
        s = (np.array([[z.real, z.imag] for z in seg]) - pts.mean(0)) @ R.T
        s = (s / scale) * 4 + np.array([GW * 2, GH * 2])
        d.line([tuple(x) for x in s], fill=255, width=3)
    return (np.array(im.resize((GW, GH), Image.BILINEAR)) > 60).astype(np.uint8)

def read_number(glyphs, rot):
    return int("".join(min(TEMPLATES, key=lambda c: int(np.abs(TEMPLATES[c].astype(int) - raster(g, rot)).sum())) for g in glyphs))

slices = {}
width = None
for f in sorted(glob.glob(os.path.join(SRC, "*.svg"))):
    kids = list(ET.parse(f).getroot())
    for k, el in enumerate(kids):
        if el.tag != NS + "path" or "st0" not in el.get("class", ""):
            continue
        g = kids[k + 1] if k + 1 < len(kids) else None
        glyphs = [glyph_points(parse_path(p.get("d"))) for p in (g if g is not None else []) if p.tag == NS + "path"]
        if not glyphs:
            print("skipping a red path without a number in", f)
            continue
        rot = orientation(glyphs)
        number = read_number(glyphs, rot)
        path = parse_path(el.get("d"))
        pts = np.array([[z.real, z.imag] for s in path
                        for z in [s.point(t) for t in np.linspace(0, 1, max(2, int(s.length()) + 2))]])
        q = pts @ rot_matrix(rot).T                 # upright: number at the bottom left
        q[:, 0] -= q[:, 0].min()
        q[:, 1] = q[:, 1].max() - q[:, 1]           # height above the bottom edge
        q /= PT_PER_MM
        w = q[:, 0].max()
        width = w if width is None else width
        xs = np.arange(0, w + 1e-6, STEP_MM)
        top = [float(q[np.abs(q[:, 0] - x) <= STEP_MM * 0.6, 1].max()) for x in xs]
        if number in slices:
            print(f"warning: slice {number:02d} found twice")
        slices[number] = top

numbers = sorted(slices)
missing = sorted(set(range(1, numbers[-1] + 1)) - set(numbers))
if missing:
    print("warning: missing slices", missing)
n = min(len(v) for v in slices.values())
data = {"author": "MUI group 3", "widthMM": round(width, 2), "stepMM": STEP_MM,
        "slices": [[round(h, 1) for h in slices[i][:n]] for i in numbers]}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
json.dump(data, open(OUT, "w"), separators=(",", ":"))
print(f"{len(numbers)} slices, {width:.1f} mm wide, max height {max(max(v) for v in slices.values()):.1f} mm -> {os.path.abspath(OUT)}")
