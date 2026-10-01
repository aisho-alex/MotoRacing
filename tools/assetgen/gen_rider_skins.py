#!/usr/bin/env python3
"""Rider skin decals via SwarmUI (Z-Image Turbo).

Generates one high-contrast white-on-black pattern per skin and converts it to
an RGBA decal: RGB stays white, the pattern lives in the alpha channel. The
runtime rider material tints it with the skin's accent color and alpha-blends
it over the chest / helmet quads, so the palette stays in the .tres while the
art comes from the texture.

Usage: python3 gen_rider_skins.py all | flame checker neon
"""

import base64
import io
import json
import os
import sys
import time
import urllib.request
from urllib.parse import quote

import numpy as np
from PIL import Image

from pbr_common import asset_path, write_license

HOST = os.environ.get("RIDER_HOST", "http://127.0.0.1:7801")
MODEL = os.environ.get("RIDER_MODEL", "ZImage/SwarmUI_Z-Image-Turbo-FP8Mix.safetensors")
STEPS = int(os.environ.get("RIDER_STEPS", "8"))
CFG = float(os.environ.get("RIDER_CFG", "1.0"))
SIZE = int(os.environ.get("RIDER_SIZE", "1024"))
SEED_BASE = 91337
BEST_OF = int(os.environ.get("RIDER_BEST", "3"))

NEG = ("text, letters, numbers, watermark, signature, logo, blurry, low "
       "contrast, grey background, gradient background, photo, 3d render, "
       "shading, drop shadow, frame, border")

FLAT = ("flat vector emblem, bold clean shapes, solid pure black background, "
        "white ink only, no shading, no gradient, centered, high contrast")

SPECS = {
    "stock": "white minimalist winged shield emblem, racing team badge, " + FLAT,
    "flame": "white tribal flame tattoo design, aggressive motorcycle decal, " + FLAT,
    "checker": "white and black racing checkered flag pattern with a diagonal "
               "speed stripe, motorsport livery, pure black background, high contrast",
    "neon": "white glowing cyberpunk circuit board lines, tech grid emblem, eprom "
            "traces, pure black background, high contrast, " + FLAT,
    "midnight": "white crescent moon with scattered stars emblem, elegant night "
                "design, " + FLAT,
    "rose": "white cherry blossom sakura petals emblem, japanese ink style, " + FLAT,
    "gold": "white laurel wreath with a crown emblem, champion badge, " + FLAT,
}


def api(route: str, payload: dict, timeout: int = 900) -> dict:
    req = urllib.request.Request(
        HOST + route, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def generate(prompt: str, seed: int) -> Image.Image:
    session = api("/API/GetNewSession", {})["session_id"]
    payload = {
        "session_id": session,
        "images": 1,
        "model": MODEL,
        "prompt": prompt,
        "negativeprompt": NEG if CFG > 1.1 else "",
        "width": SIZE,
        "height": SIZE,
        "steps": STEPS,
        "cfg_scale": CFG,
        "seed": seed,
    }
    resp = api("/API/GenerateText2Image", payload)
    if "images" not in resp:
        raise RuntimeError("API error: " + json.dumps(resp)[:300])
    img_path = resp["images"][0]
    if isinstance(img_path, dict):
        img_path = img_path["image"]
    with urllib.request.urlopen(f"{HOST}/{quote(img_path)}", timeout=120) as r:
        return Image.open(io.BytesIO(r.read())).convert("L")


def to_decal(img: Image.Image, lo: float = 0.30, hi: float = 0.72) -> Image.Image:
    """Luminance -> alpha mask (white RGB) with a soft contrast curve."""
    a = np.asarray(img.resize((SIZE, SIZE), Image.LANCZOS)).astype(np.float64) / 255.0
    a = np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    a = a * a * (3.0 - 2.0 * a)  # smoothstep
    rgba = np.zeros((*a.shape, 4), dtype=np.uint8)
    rgba[..., 0:3] = 255
    rgba[..., 3] = (a * 255.0).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def score(img: Image.Image) -> float:
    """Prefer patterns that fill a healthy fraction of the emblem."""
    a = np.asarray(img.convert("L")).astype(np.float64) / 255.0
    cover = float(((a > 0.4) & (a < 0.95)).mean())
    return -abs(cover - 0.35) + float(a.std()) * 0.2


def build(skin_id: str) -> None:
    if skin_id not in SPECS:
        raise SystemExit("unknown skin: %s" % skin_id)
    prompt = SPECS[skin_id]
    best = None
    best_score = -1e9
    for i in range(BEST_OF):
        try:
            img = generate(prompt, SEED_BASE + i * 101 + sum(map(ord, skin_id)))
        except Exception as exc:  # noqa: BLE001
            print("  seed %d failed: %s" % (i, exc))
            time.sleep(2)
            continue
        s = score(img)
        if s > best_score:
            best, best_score = img, s
    if best is None:
        raise SystemExit("generation failed for %s" % skin_id)
    decal = to_decal(best)
    out = asset_path(f"skins/{skin_id}/decal.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    decal.save(out)
    write_license(
        f"{out}.license", "decal.png",
        f"SwarmUI Z-Image Turbo (seed~{SEED_BASE}, best-of {BEST_OF})",
        f"rider skin '{skin_id}' chest/helmet decal; white RGB + pattern alpha",
    )
    print("%s: ok (score %.3f)" % (skin_id, best_score))


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ids = list(SPECS) if (not args or args[0] == "all") else args
    for skin_id in ids:
        build(skin_id)


if __name__ == "__main__":
    main()
