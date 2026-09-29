#!/usr/bin/env python3
"""Car livery generation via SwarmUI img2img over the original UV atlas.

Uses the running SwarmUI instance (127.0.0.1:7802) to repaint the grayscale
baseColor atlas (assets/car_0.webp) into a racing livery while keeping the
UV island structure (denoise ~0.5). Also derives shared normal/ORM maps from
the original atlas luminance.

Usage: python3 gen_livery_swarm.py [index] [color description]
  e.g. python3 gen_livery_swarm.py 0 "red and white"
"""

import base64
import io
import json
import os
import sys
import urllib.request
from urllib.parse import quote

import numpy as np
from PIL import Image

from pbr_common import DATE, asset_path, normal_map, orm_map, save_png, write_license

HOST = "http://127.0.0.1:7802"
MODEL = "OfficialStableDiffusion/sd_xl_base_1.0.safetensors"
SEED_BASE = 20260924
DENOISE = 0.5
OUT_SIZE = 1024  # mobile budget: liveries 1024^2

NEG = (
    "photo, photograph, perspective view, 3d render, scene, background, room, "
    "lighting, shadows, reflections, glossy highlights, text, letters, numbers, "
    "watermark, logo, blurry, noise"
)


def api(route: str, payload: dict, timeout: int = 600) -> dict:
    req = urllib.request.Request(
        HOST + route,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def to_data_url(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def build_prompt(colors: str) -> str:
    return (
        f"seamless texture atlas for a race car, arcade racing livery, {colors} paint, "
        "clean decal stripes across body panels, glossy clear coat, smooth color blocks, "
        "texture map layout, flat even colors, no lighting, no shadows"
    )


def generate(index: int, colors: str) -> Image.Image:
    src = Image.open(asset_path("car_0.webp")).convert("RGB")
    session = api("/API/GetNewSession", {})["session_id"]
    payload = {
        "session_id": session,
        "images": 1,
        "model": MODEL,
        "prompt": build_prompt(colors),
        "negativeprompt": NEG,
        "width": OUT_SIZE,
        "height": OUT_SIZE,
        "steps": 30,
        "cfg_scale": 7.0,
        "seed": SEED_BASE + index,
        "initimage": to_data_url(src),
        "initimagecreativity": DENOISE,
    }
    resp = api("/API/GenerateText2Image", payload)
    img_path = resp["images"][0]
    if isinstance(img_path, dict):
        img_path = img_path["image"]
    with urllib.request.urlopen(f"{HOST}/{quote(img_path)}", timeout=120) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGB")


def derivatives() -> None:
    """Shared normal/ORM from the ORIGINAL atlas luminance (panel detail)."""
    lum = np.asarray(Image.open(asset_path("car_0.webp")).convert("L")).astype(np.float64) / 255.0
    out = asset_path("cars/sport_01")
    save_png(f"{out}/normal.png", normal_map(lum, strength=1.2))
    rough = np.clip(0.30 + 0.25 * (1.0 - lum), 0.0, 1.0)
    metal = np.clip(0.20 + 0.15 * lum, 0.0, 1.0)
    ao = np.clip(0.75 + 0.25 * lum, 0.0, 1.0)
    save_png(f"{out}/orm.png", orm_map(ao, rough, metal))
    write_license(
        f"{out}/normal.png.license", "normal.png",
        "procedural (tools/assetgen/gen_livery_swarm.py)",
        "height = luminance of original car_0.webp atlas, wrap gradient",
    )
    write_license(
        f"{out}/orm.png.license", "orm.png",
        "procedural (tools/assetgen/gen_livery_swarm.py)",
        "car paint: roughness ~0.3-0.55, light metallic, AO from luminance",
    )


PRIMARY_COLORS = {
    "red": np.array([0.78, 0.10, 0.10]),
    "blue": np.array([0.10, 0.28, 0.75]),
    "orange": np.array([0.90, 0.42, 0.06]),
    "green": np.array([0.10, 0.55, 0.16]),
    "yellow": np.array([0.92, 0.75, 0.08]),
    "black": np.array([0.12, 0.12, 0.13]),
}


def recolor(src_l: Image.Image, primary: np.ndarray, stripes: bool = True) -> Image.Image:
    """Gradient-map the grayscale atlas: dark -> carbon trim, mid -> primary
    paint, light -> white. Per-pixel transform, so UV islands are preserved
    exactly. Optional diagonal stripes drawn inside the paint band only."""
    lum = np.asarray(src_l).astype(np.float64) / 255.0
    white = np.array([0.93, 0.93, 0.95])
    carbon = np.array([0.06, 0.06, 0.07])
    stops = [
        (0.00, carbon),
        (0.12, carbon * 1.6),
        (0.42, primary * 0.55),
        (0.55, primary),
        (0.78, primary),
        (0.86, white),
        (1.00, np.array([0.99, 0.99, 1.00])),
    ]
    out = np.zeros((*lum.shape, 3))
    for i in range(len(stops) - 1):
        l0, c0 = stops[i]
        l1, c1 = stops[i + 1]
        m = (lum >= l0) & (lum <= l1)
        t = ((lum - l0) / max(l1 - l0, 1e-6))[m][:, None]
        out[m] = c0[None, :] * (1.0 - t) + c1[None, :] * t

    if stripes:
        h, w = lum.shape
        vv, uu = np.mgrid[0:h, 0:w]
        diag = (uu + vv * 2.2) / 70.0
        band = np.abs((diag % 1.0) - 0.5) < 0.09
        paint_zone = (lum > 0.42) & (lum < 0.78)
        mask = (band & paint_zone)[..., None] * 0.85
        out = out * (1.0 - mask) + white[None, None, :] * mask
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    use_sd = "--sd" in sys.argv
    index = int(args[0]) if len(args) > 0 else 0
    colors = args[1] if len(args) > 1 else "red and white"
    out = asset_path(f"cars/sport_01/livery_{index}.webp")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    src_rgb = Image.open(asset_path("car_0.webp")).convert("RGB")
    primary_name = colors.split()[0]
    primary = PRIMARY_COLORS.get(primary_name, PRIMARY_COLORS["red"])
    if use_sd:
        img = generate(index, colors)
    else:
        img = recolor(Image.open(asset_path("car_0.webp")).convert("L"), primary)
    if img.size != (OUT_SIZE, OUT_SIZE):
        img = img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    img.save(out, quality=92)
    tool = (
        f"SwarmUI img2img (SDXL base, denoise={DENOISE}, seed={SEED_BASE + index})"
        if use_sd else
        f"procedural gradient-map recolor of car_0.webp (primary={primary_name})"
    )
    write_license(f"{out}.license", f"livery_{index}.webp", tool, f"colors: {colors}")
    print(f"livery_{index}: ok ({colors})")
    derivatives()
    print("derivatives: normal.png, orm.png ok")


if __name__ == "__main__":
    main()
