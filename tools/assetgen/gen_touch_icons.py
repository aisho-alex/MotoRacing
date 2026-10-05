#!/usr/bin/env python3
"""Flat white touch-gamepad glyphs (PIL, no backend).

White silhouettes on transparent alpha, meant to be tinted at runtime via
modulate. Solid flat shapes with no gradients, matching the cel UI.

Outputs 256x256 RGBA PNGs into assets/ui/touch/:
  pedal_gas, pedal_brake, nitro, fist, boot, chevron_left, chevron_right
"""

import os

from PIL import Image, ImageDraw

from pbr_common import asset_path, write_license

S = 256
SS = 4
W = S * SS
TOOL = "procedural synthesis (tools/assetgen/gen_touch_icons.py)"
OUT = "ui/touch"


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("L", (W, W), 0)
    return img, ImageDraw.Draw(img)


def _down(img: Image.Image) -> Image.Image:
    mask = img.resize((S, S), Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(mask)
    return out


def _rr(d, box, radius, fill=255):
    x0, y0, x1, y1 = (int(v * SS) for v in box)
    d.rounded_rectangle((x0, y0, x1, y1), radius=int(radius * SS), fill=fill)


def _poly(d, pts, fill=255):
    d.polygon([(int(x * SS), int(y * SS)) for x, y in pts], fill=fill)


def pedal_gas() -> Image.Image:
    img, d = _canvas()
    _rr(d, (70, 38, 186, 226), 24)
    for y in (84, 118, 152, 186):
        _rr(d, (88, y - 6, 168, y + 6), 6, fill=0)
    return _down(img)


def pedal_brake() -> Image.Image:
    img, d = _canvas()
    _rr(d, (48, 66, 208, 198), 18)
    for x in (100, 156):
        _rr(d, (x - 5, 84, x + 5, 180), 5, fill=0)
    for y in (106, 158):
        _rr(d, (64, y - 5, 192, y + 5), 5, fill=0)
    return _down(img)


def _smooth(pts: list, iters: int = 3) -> list:
    for _ in range(iters):
        out = []
        n = len(pts)
        for i in range(n):
            p, q = pts[i], pts[(i + 1) % n]
            out.append((0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]))
            out.append((0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1]))
        pts = out
    return pts


FLAME_OUTLINE = [
    (128, 224), (172, 212), (198, 184), (188, 142), (174, 98),
    (150, 122), (138, 32), (112, 78), (96, 118), (70, 170),
    (90, 206),
]


def nitro() -> Image.Image:
    img, d = _canvas()
    _poly(d, _smooth(FLAME_OUTLINE))
    return _down(img)


def fist() -> Image.Image:
    img, d = _canvas()
    _rr(d, (66, 116, 192, 228), 30)
    fingers = [(74, 84), (108, 72), (142, 76), (176, 92)]
    for x0, y0 in fingers:
        _rr(d, (x0, y0, x0 + 26, 156), 14)
    _rr(d, (50, 166, 150, 208), 21)
    _rr(d, (50, 150, 152, 166), 7, fill=0)
    return _down(img)


def boot() -> Image.Image:
    img, d = _canvas()
    _rr(d, (34, 190, 222, 228), 19)
    _poly(d, [(96, 214), (150, 170), (196, 170), (196, 214)])
    _rr(d, (48, 86, 114, 210), 24)
    _rr(d, (142, 168, 220, 202), 17)
    _rr(d, (40, 78, 128, 116), 16)
    return _down(img)


def chevron_right() -> Image.Image:
    img, d = _canvas()
    _poly(d, [(62, 34), (172, 128), (62, 222), (104, 222), (214, 128), (104, 34)])
    return _down(img)


def chevron_left() -> Image.Image:
    return chevron_right().transpose(Image.FLIP_LEFT_RIGHT)


ICONS = {
    "pedal_gas": pedal_gas,
    "pedal_brake": pedal_brake,
    "nitro": nitro,
    "fist": fist,
    "boot": boot,
    "chevron_right": chevron_right,
    "chevron_left": chevron_left,
}


def _sheet(images: dict) -> None:
    names = list(images)
    cols = 4
    rows = (len(names) + cols - 1) // cols
    cell = S + 16
    sheet = Image.new("RGB", (cols * cell, rows * cell), (32, 44, 58))
    for i, name in enumerate(names):
        cx = (i % cols) * cell + 8
        cy = (i // cols) * cell + 8
        sheet.paste(images[name], (cx, cy), images[name])
    os.makedirs("/tmp/opencode", exist_ok=True)
    sheet.save("/tmp/opencode/touch_icons_sheet.png")


def main() -> None:
    out_dir = asset_path(OUT)
    os.makedirs(out_dir, exist_ok=True)
    made = {}
    for name, fn in ICONS.items():
        icon = fn()
        path = os.path.join(out_dir, f"{name}.png")
        icon.save(path)
        made[name] = icon
        write_license(f"{path}.license", f"{name}.png", TOOL, "flat white glyph, tinted at runtime")
        print(f"touch icon {name}: ok")
    _sheet(made)
    print("gen_touch_icons: all ok")


if __name__ == "__main__":
    main()
