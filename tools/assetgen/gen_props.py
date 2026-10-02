#!/usr/bin/env python3
"""Billboard prop sprites via SwarmUI (Qwen-Image) on a magenta chroma key.

Generates side-view game sprites, keys out the magenta background, defringes,
crops to content and resizes to the mobile budget. Outputs PNG+alpha into
assets/environments/<biome>/props/.

Usage: python3 gen_props.py all | city desert alpine coast
"""

import base64
import io
import json
import os
import sys
import urllib.request
import zlib
from urllib.parse import quote

import numpy as np
import cv2
from PIL import Image, ImageFilter

from pbr_common import asset_path, write_license

HOST = os.environ.get("PROPS_HOST", "http://127.0.0.1:7801")
MODEL = "Qwen2.1/qwen_image_2.1_int8_convrot.safetensors"
STEPS = 28
CFG = 2.8
GEN = 768
MAX_H = 512
MAGENTA = np.array([1.0, 0.0, 1.0])

NEG = ("ground, soil, grass, horizon, sky, landscape, shadows cast on "
       "background, drop shadow, multiple objects, multiple trees, people, "
       "text, watermark, frame, border, cut-off object, blurry, photorealistic, "
       "photo, photograph, realistic, low detail, night, blue tint, winter, "
       "dead tree")

SPECS = {
    "city": [
        ("tree_plane_a", "one single mature London plane tree with a dense irregular "
         "green summer crown and textured mottled bark"),
        ("tree_maple_a", "one single broad summer maple tree with a full natural "
         "crown and visible trunk"),
        ("tree_linden_a", "one single tall lime tree with a wide asymmetrical green "
         "crown and textured bark"),
        ("tree_birch_a", "one single slender silver birch with white bark and airy "
         "fine summer foliage"),
        ("tree_poplar_a", "one single tall narrow black poplar covered in bright "
         "green summer leaves, dense foliage and a visible trunk"),
        ("tree_oak_a", "one single massive old oak with a thick trunk and broad "
         "natural crown"),
        ("bush_city_a", "one single dense green city shrub with natural uneven "
         "leaves"),
        ("bush_hedge_a", "one single low rounded boxwood shrub with fine realistic "
         "leaves"),
    ],
    "desert": [
        ("cactus_saguaro_a", "single tall saguaro cactus with two arms, game sprite"),
        ("cactus_saguaro_b", "single small barrel cactus cluster, game sprite"),
        ("rock_desert_a", "single large weathered desert boulder, game sprite"),
    ],
    "alpine": [
        ("pine_spruce_a", "single tall narrow spruce conifer tree, dark green, "
         "game sprite"),
        ("pine_spruce_b", "single conifer pine tree with layered branches, light "
         "snow dusting on branches, game sprite"),
        ("rock_snow_a", "single grey boulder with snow patches, game sprite"),
    ],
    "coast": [
        ("palm_a", "single tall palm tree with spreading fronds, leaning trunk, "
         "game sprite"),
        ("palm_b", "single short palm tree with dense fronds, game sprite"),
        ("bush_coast_a", "single low coastal shrub with yellow-green leaves, "
         "game sprite"),
    ],
    "canyon": [
        ("rock_mesa_a", "single tall layered red sandstone rock spire, desert mesa "
         "formation, game sprite"),
        ("rock_canyon_a", "single weathered orange canyon boulder with horizontal "
         "strata, game sprite"),
        ("bush_dry_a", "single low dry desert shrub with sparse grey-green twigs, "
         "game sprite"),
        ("tree_juniper_a", "single gnarled dry juniper tree with twisted trunk and "
         "sparse foliage, game sprite"),
    ],
    "sakura": [
        ("sakura_a", "single large cherry blossom tree in full pink bloom, dense "
         "canopy of pink flowers, dark trunk, game sprite"),
        ("sakura_b", "single smaller weeping cherry tree with cascading pale pink "
         "blossoms, game sprite"),
        ("bush_sakura_a", "single low rounded green shrub with a few pink blossoms, "
         "game sprite"),
        ("rock_garden_a", "single grey ornamental garden stone with moss, game sprite"),
    ],
    "volcano": [
        ("basalt_columns_a", "single cluster of dark basalt column rocks, volcanic "
         "formation, game sprite"),
        ("rock_volcanic_a", "single jagged black volcanic boulder with porous texture, "
         "game sprite"),
        ("tree_charred_a", "single charred dead tree with black burned trunk and "
         "bare branches, game sprite"),
        ("bush_ash_a", "single low ash-grey volcanic shrub with sparse dark leaves, "
         "game sprite"),
    ],
}


def api(route: str, payload: dict, timeout: int = 900) -> dict:
    req = urllib.request.Request(
        HOST + route, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def wait_backend(session: str, timeout_s: int = 240) -> None:
    import time
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            st = api("/API/ListBackends", {"session_id": session}, timeout=30)
            raw = json.dumps(st)
            if '"status": "running"' in raw or '"status":"running"' in raw:
                return
        except Exception:
            pass
        import time as t
        t.sleep(10)
    raise RuntimeError("backend not running")


def generate(prompt: str, seed: int) -> Image.Image:
    session = api("/API/GetNewSession", {})["session_id"]
    wait_backend(session)
    payload = {
        "session_id": session,
        "images": 1,
        "model": MODEL,
        "prompt": prompt,
        "negativeprompt": NEG,
        "width": GEN,
        "height": GEN,
        "steps": STEPS,
        "cfg_scale": CFG,
        "seed": seed,
    }
    resp = api("/API/GenerateText2Image", payload)
    if "images" not in resp:
        print("gen failed: " + json.dumps(resp)[:300])
        return None
    img_path = resp["images"][0]
    if isinstance(img_path, dict):
        img_path = img_path["image"]
    with urllib.request.urlopen(f"{HOST}/{quote(img_path)}", timeout=120) as r:
        img = Image.open(io.BytesIO(r.read())).convert("RGB")
    if img.size != (GEN, GEN):
        img = img.resize((GEN, GEN), Image.LANCZOS)
    return img


def chroma_key(img: Image.Image) -> Image.Image:
    """Remove a variable-brightness magenta background without eating twigs."""
    a = np.asarray(img).astype(np.float64) / 255.0
    rgb = a[..., :3]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hsv = np.asarray(img.convert("HSV")).astype(np.float64) / 255.0
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    hue_dist = np.abs(hue - (5.0 / 6.0))
    hue_dist = np.minimum(hue_dist, 1.0 - hue_dist)
    excess = np.clip(np.minimum(r, b) - g, 0.0, 1.0)
    color_score = np.clip((excess - 0.04) / 0.18, 0.0, 1.0) * np.clip(
        (sat - 0.08) / 0.15, 0.0, 1.0)
    hue_score = np.clip((0.14 - hue_dist) / 0.08, 0.0, 1.0) * np.clip(
        (sat - 0.20) / 0.25, 0.0, 1.0)
    magenta_score = np.maximum(color_score, hue_score)

    alpha = np.clip((0.26 - magenta_score) / 0.12, 0.0, 1.0)
    neutral_object = (sat < 0.18) & (val > 0.10)
    alpha[neutral_object] = 1.0

    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.5))).astype(np.float64) / 255.0
    alpha = keep_main_component(alpha)
    alpha[alpha < 0.06] = 0.0

    # Despill only near the cutout edge; interior colours stay untouched.
    spill = np.clip(1.0 - alpha * 2.0, 0.0, 1.0)[..., None]
    lum = rgb.mean(axis=-1, keepdims=True)
    rgb = rgb * (1.0 - spill * 0.9) + lum * spill * 0.9
    out = np.dstack([rgb, alpha[..., None]])
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def keep_main_component(alpha: np.ndarray) -> np.ndarray:
    """Drop chroma residue and detached image noise; keep significant fragments."""
    mask = alpha > 0.04
    if not mask.any():
        return alpha
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
    if count <= 2:
        return alpha
    largest = int(np.argmax(stats[1:, cv2.CC_STAT_AREA])) + 1
    threshold = max(32.0, stats[largest, cv2.CC_STAT_AREA] * 0.05)
    keep = [i for i in range(1, count) if stats[i, cv2.CC_STAT_AREA] >= threshold]
    clean = alpha.copy()
    remove = np.isin(labels, [i for i in range(1, count) if i not in keep])
    clean[remove] = 0.0
    return clean


def crop_content(img: Image.Image, pad: int = 4) -> Image.Image:
    mask = np.asarray(img.getchannel("A")) > 0.08 * 255.0
    ys, xs = np.where(mask)
    if ys.size == 0:
        return img
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(img.width, x1 + pad)
    # Do not pad the bottom: the lowest visible pixel is the grounding point.
    y1 = min(img.height, y1)
    return img.crop((x0, y0, x1, y1))


def reprocess_existing(biome: str) -> None:
    out_dir = asset_path(f"environments/{biome}/props")
    for path in sorted(os.listdir(out_dir)):
        if not path.endswith(".png"):
            continue
        full = f"{out_dir}/{path}"
        img = Image.open(full).convert("RGBA")
        img = crop_content(chroma_key(img))
        if img.height > MAX_H:
            img = img.resize((max(1, int(round(img.width * MAX_H / img.height))), MAX_H), Image.LANCZOS)
        if img.width > MAX_H:
            img = img.resize((MAX_H, max(1, int(round(img.height * MAX_H / img.width)))), Image.LANCZOS)
        img.save(full)
        print(f"{biome}/{path}: reprocessed {img.size}")


def trim_existing(biome: str) -> None:
    """Safely crop already-keyed cutouts without reprocessing RGB."""
    out_dir = asset_path(f"environments/{biome}/props")
    for path in sorted(os.listdir(out_dir)):
        if not path.endswith(".png"):
            continue
        full = f"{out_dir}/{path}"
        img = crop_content(Image.open(full).convert("RGBA"))
        if img.height > MAX_H:
            img = img.resize((max(1, int(round(img.width * MAX_H / img.height))), MAX_H), Image.LANCZOS)
        if img.width > MAX_H:
            img = img.resize((MAX_H, max(1, int(round(img.height * MAX_H / img.width)))), Image.LANCZOS)
        img.save(full)
        print(f"{biome}/{path}: trimmed {img.size}")


def main() -> None:
    biomes = sys.argv[1:] or ["all"]
    if biomes and biomes[0] == "--trim":
        for biome in (biomes[1:] or ["all"]):
            for item in (list(SPECS) if biome == "all" else [biome]):
                trim_existing(item)
        return
    if biomes and biomes[0] == "--reprocess":
        for biome in (biomes[1:] or ["all"]):
            if biome == "all":
                biome_list = list(SPECS)
            else:
                biome_list = [biome]
            for item in biome_list:
                reprocess_existing(item)
        return
    if biomes == ["all"]:
        biomes = list(SPECS)
    for biome in biomes:
        out_dir = asset_path(f"environments/{biome}/props")
        os.makedirs(out_dir, exist_ok=True)
        for i, (name, extra) in enumerate(SPECS[biome]):
            out = f"{out_dir}/{name}.png"
            if os.path.exists(out):
                print(f"{biome}/{name}: exists, skip")
                continue
            prompt = (f"{extra}, complete object, full silhouette visible, side "
                      f"elevation, flat cel-shaded cartoon game asset, hand-painted "
                      f"stylized illustration, bold clean shapes, bright saturated "
                      f"colors, simple readable forms, centered, isolated on a solid "
                      f"pure magenta chroma-key background, even neutral lighting, "
                      f"no ground, no cast shadow, clean edges")
            seed = 9100 + zlib.crc32(f"{biome}/{name}".encode()) % 20000
            img = generate(prompt, seed)
            if img is None:
                print(f"{biome}/{name}: FAILED")
                continue
            img = chroma_key(img)
            img = crop_content(img)
            if img.height < GEN * 0.35 or img.width < GEN * 0.12:
                print(f"{biome}/{name}: suspicious tiny result {img.size}")
            if img.height > MAX_H:
                w = max(1, int(round(img.width * MAX_H / img.height)))
                img = img.resize((w, MAX_H), Image.LANCZOS)
            if img.width > MAX_H:
                h = max(1, int(round(img.height * MAX_H / img.width)))
                img = img.resize((MAX_H, h), Image.LANCZOS)
            img.save(out)
            write_license(f"{out}.license", f"{name}.png",
                          "SwarmUI Qwen-Image chroma-key cutout",
                          f"seed: {seed}; prompt: {prompt}")
            print(f"{biome}/{name}: ok {img.size} seed={seed}")
    print("props: done")


if __name__ == "__main__":
    main()
