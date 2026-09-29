#!/usr/bin/env python3
"""Store/app art: Android adaptive icon layers, 512 icon, feature graphic.

Uses the bundled ChakraPetch-Bold for text. Outputs:
  assets/ui/icons/icon_bg_432.png   (adaptive background layer)
  assets/ui/icons/icon_fg_432.png   (adaptive foreground layer, transparent)
  assets/ui/icons/icon_512.png      (flat 512 icon for store/desktop)
  assets/store/feature_graphic.png  (1024x500 Google Play feature graphic)
"""

from PIL import Image, ImageDraw, ImageFont

from pbr_common import asset_path, write_license

TOOL = "procedural synthesis (tools/assetgen/gen_art.py)"
FONT = asset_path("ui/fonts/ChakraPetch-Bold.ttf")


def gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    return img


def draw_car(draw: ImageDraw.ImageDraw, cx: int, cy: int, s: float,
             body: tuple, accent: tuple, wheel: tuple) -> None:
    """Stylized side-view rally car centered at (cx, cy), scale s."""
    def r(box, rad, fill):
        draw.rounded_rectangle(
            [(cx + box[0] * s, cy + box[1] * s), (cx + box[2] * s, cy + box[3] * s)],
            radius=rad * s, fill=fill)

    r((-150, -20, 150, 60), 34, body)          # body
    r((-85, -72, 55, -5), 30, body)            # cabin
    r((-70, -58, 40, -14), 18, (34, 42, 60))   # window
    r((-140, 2, -20, 20), 8, accent)           # accent stripe
    r((-150, 34, -90, 48), 6, accent)
    for wx in (-92, 92):                        # wheels
        draw.ellipse([(cx + (wx - 34) * s, cy + (44 - 34) * s),
                      (cx + (wx + 34) * s, cy + (44 + 34) * s)], fill=wheel)
        draw.ellipse([(cx + (wx - 14) * s, cy + (44 - 14) * s),
                      (cx + (wx + 14) * s, cy + (44 + 14) * s)], fill=(190, 195, 205))


def checkers(draw: ImageDraw.ImageDraw, x0: int, y0: int, cell: int, cols: int, rows: int) -> None:
    for ry in range(rows):
        for rx in range(cols):
            if (rx + ry) % 2 == 0:
                draw.rectangle([x0 + rx * cell, y0 + ry * cell,
                                x0 + (rx + 1) * cell - 1, y0 + (ry + 1) * cell - 1],
                               fill=(235, 235, 240))


def icon_layers() -> None:
    out = asset_path("ui/icons")

    bg = gradient((432, 432), (255, 106, 20), (196, 30, 24))
    bg.save(f"{out}/icon_bg_432.png")

    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    # white car + dark wheels; content kept inside the adaptive safe zone
    draw_car(d, 216, 208, 1.05, (250, 250, 252), (200, 34, 28), (30, 32, 40))
    checkers(d, 108, 330, 18, 12, 2)
    fg.save(f"{out}/icon_fg_432.png")

    icon = bg.convert("RGBA")
    icon.alpha_composite(fg)
    icon.resize((512, 512), Image.LANCZOS).convert("RGB").save(f"{out}/icon_512.png")

    write_license(f"{out}/icon_bg_432.png.license", "icon_bg_432.png", TOOL, "orange gradient")
    write_license(f"{out}/icon_fg_432.png.license", "icon_fg_432.png", TOOL, "rally car silhouette + checkers")
    write_license(f"{out}/icon_512.png.license", "icon_512.png", TOOL, "composite of adaptive layers")
    print("icons: ok")


def feature_graphic() -> None:
    img = gradient((1024, 500), (16, 18, 30), (52, 16, 20)).convert("RGBA")
    d = ImageDraw.Draw(img)
    checkers(d, 0, 436, 24, 43, 3)

    title = Image.new("RGBA", (1024, 160), (0, 0, 0, 0))
    td = ImageDraw.Draw(title)
    font_title = ImageFont.truetype(FONT, 108)
    text = "SIMPLE RACING"
    w = td.textlength(text, font=font_title)
    td.text(((1024 - w) / 2, 0), text, font=font_title, fill=(255, 214, 64))
    # slight drop shadow
    sh = Image.new("RGBA", (1024, 160), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.text(((1024 - w) / 2 + 5, 6), text, font=font_title, fill=(0, 0, 0, 160))
    img.alpha_composite(sh, (0, 96))
    img.alpha_composite(title, (0, 90))

    sub_font = ImageFont.truetype(FONT, 40)
    sub = "ARCADE   RACING   4 CARS   4 TRACKS"
    sw = d.textlength(sub, font=sub_font)
    d.text(((1024 - sw) / 2, 262), sub, font=sub_font, fill=(235, 235, 240))

    draw_car(d, 830, 385, 0.62, (240, 240, 244), (226, 48, 36), (25, 27, 35))
    d.text((60, 380), "WIN  UNLOCK  REPEAT", font=ImageFont.truetype(FONT, 30),
           fill=(255, 214, 64, 200))

    out = asset_path("store/feature_graphic.png")
    img.convert("RGB").save(out)
    write_license(out + ".license", "feature_graphic.png", TOOL, "title art, ChakraPetch font (OFL)")
    print("feature graphic: ok")


if __name__ == "__main__":
    icon_layers()
    feature_graphic()
