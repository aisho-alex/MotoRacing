#!/usr/bin/env python3
"""Photorealistic seamless PBR textures via SwarmUI (Z-Image Turbo).

Generates albedo at high resolution, makes it tileable with an offset-heal
wrap blend, sharpens on downsize, then derives normal (from the high-res
luminance) and ORM maps. Picks the best of several seeds per material.

Usage: python3 gen_sdxl_tex.py all | city_road city_terrain --force
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
from PIL import Image, ImageFilter

from pbr_common import (
    asset_path,
    normal_map,
    orm_map,
    save_png,
    save_webp,
    write_license,
)

HOST = os.environ.get("TEX_HOST", "http://127.0.0.1:7801")
MODEL = os.environ.get("TEX_MODEL", "ZImage/SwarmUI_Z-Image-Turbo-FP8Mix.safetensors")
STEPS = int(os.environ.get("TEX_STEPS", "8"))
CFG = float(os.environ.get("TEX_CFG", "1.0"))
GEN_SIZE = int(os.environ.get("TEX_GEN", "1536"))
OUT_SIZE = 1024
BEST_OF = int(os.environ.get("TEX_BEST", "3"))
SEED_BASE = 7711

QUALITY = ("seamless tileable texture, flat even diffuse lighting, top-down "
           "orthographic view, pbr albedo map, high detail")
QUALITY_FACADE = ("seamless tileable texture, flat orthographic front view, flat "
                  "even diffuse lighting, no shading gradient, high detail")
NEG = ("shadows, lighting, light gradient, vignette, border, frame, objects, props, "
       "text, watermark, lines, blurry, jpeg artifacts, people, cars, cartoon, "
       "painting, illustration, oversaturated colors")
ROAD_NEG_EXTRA = (", tiles, tile joints, ceramic, concrete slabs, paving stones, "
                  "grid lines, snow, ice, water, wood planks, fabric, grass, plants, "
                  "sand dune, flowers")
FACADE_NEG_EXTRA = (", tiles, ceramic, plain flat blank wall, grid pattern, snow, "
                    "grass, plants, sky, blurry")
TERRAIN_NEG_EXTRA = (", tiles, ceramic, concrete slabs, paving, grid pattern, wood, "
                     "fabric, blurry")
KEY_NEG_EXTRA = {
    "alpine_terrain": ", grass, plants, sand, dirt",
    "desert_terrain": ", grass, plants, water, concrete",
    "coast_terrain": ", concrete, tiles, water, ice",
    "volcano_terrain": ", concrete, tiles, ice, snow",
}

SPECS = {
    "city_road": {
        "prompt": "seamless tileable dark grey asphalt road surface, photorealistic, "
                  "coarse aggregate stones, fine gravel, sparse hairline cracks, a few "
                  "dark tar repair patches, subtle tyre polish bands, " + QUALITY,
        "rough": 0.92, "normal_strength": 2.2,
    },
    "city_terrain": {
        "prompt": "seamless tileable mowed lawn grass texture, photorealistic, natural "
                  "medium green turf, mixed grass blades with a few clover leaves and "
                  "subtle dry yellow patches, " + QUALITY,
        "rough": 0.85, "normal_strength": 1.7,
    },
    "desert_road": {
        "prompt": "seamless tileable sun-bleached grey asphalt road surface, "
                  "photorealistic, coarse aggregate stones, fine gravel, cracked tar "
                  "patches, drifting sand grains, " + QUALITY,
        "rough": 0.9, "normal_strength": 2.2,
    },
    "desert_terrain": {
        "prompt": "seamless tileable desert sand ground texture, photorealistic, warm "
                  "beige sand with soft wind ripples, scattered pebbles and coarse "
                  "grains, " + QUALITY,
        "rough": 0.8, "normal_strength": 1.6,
    },
    "alpine_road": {
        "prompt": "seamless tileable cold mountain asphalt road surface, "
                  "photorealistic, coarse aggregate stones, fine gravel, dark grey worn "
                  "tarmac with white salt stains and fine frost cracks, " + QUALITY,
        "rough": 0.88, "normal_strength": 2.2,
    },
    "alpine_terrain": {
        "prompt": "seamless tileable clean snow surface texture, photorealistic, "
                  "subtle wind packed texture and faint sparkle, soft blue tint in "
                  "shallow dips, a few tiny ice crystals, " + QUALITY,
        "rough": 0.6, "normal_strength": 1.5,
    },
    "coast_road": {
        "prompt": "seamless tileable weathered grey asphalt road surface, "
                  "photorealistic, coarse aggregate stones, fine gravel, sun-faded "
                  "tarmac with sandy dust and fine hairline cracks, " + QUALITY,
        "rough": 0.9, "normal_strength": 2.1,
    },
    "coast_terrain": {
        "prompt": "seamless tileable coastal sand ground texture, photorealistic, warm "
                  "pale sand with irregular scattered marram grass tufts and shell "
                  "fragments, " + QUALITY,
        "rough": 0.82, "normal_strength": 1.7,
    },
    "canyon_road": {
        "prompt": "seamless tileable dusty grey-brown asphalt road surface, "
                  "photorealistic, coarse aggregate stones, fine gravel, cracked tar "
                  "patches with desert dust drift, " + QUALITY,
        "rough": 0.93, "normal_strength": 2.2,
    },
    "canyon_terrain": {
        "prompt": "seamless tileable red rock canyon ground texture, photorealistic, "
                  "orange sandstone gravel, cracked dry earth, scattered pebbles and "
                  "rocks, " + QUALITY,
        "rough": 0.9, "normal_strength": 1.9,
    },
    "sakura_road": {
        "prompt": "seamless tileable smooth grey asphalt road surface, photorealistic, "
                  "fine aggregate stones, sparse hairline cracks, a few fallen pink "
                  "cherry blossom petals, " + QUALITY,
        "rough": 0.9, "normal_strength": 2.0,
    },
    "sakura_terrain": {
        "prompt": "seamless tileable short bright green spring lawn texture, "
                  "photorealistic, fresh natural turf with fallen pink cherry blossom "
                  "petals and subtle dirt patches, " + QUALITY,
        "rough": 0.85, "normal_strength": 1.6,
    },
    "volcano_road": {
        "prompt": "seamless tileable dark charcoal volcanic basalt asphalt road "
                  "surface, photorealistic, coarse black aggregate stones, fine gravel, "
                  "worn tarmac dusted with grey ash and fine cracks, " + QUALITY,
        "rough": 0.88, "normal_strength": 2.2,
    },
    "volcano_terrain": {
        "prompt": "seamless tileable black volcanic ground texture, photorealistic, "
                  "rough porous lava rock, grey ash, scoria pebbles and cooling cracks, "
                  + QUALITY,
        "rough": 0.92, "normal_strength": 2.0,
    },
}

# building facades per biome: (suffix, prompt, roughness)
FACADES = {
    "city": [
        ("a", "seamless tileable modern office building facade, dark low-iron glass "
              "curtain wall with pale stone mullions and subtle floor variation, "
              "photorealistic, " + QUALITY_FACADE, 0.45),
        ("b", "seamless tileable weathered red-brown brick apartment facade in a "
              "realistic mortar bond, recessed windows with grey stone lintels and "
              "subtle urban grime, photorealistic, " + QUALITY_FACADE, 0.82),
        ("c", "seamless tileable contemporary concrete and glass tower facade, warm "
              "grey panels, narrow recessed windows and visible joints, "
              "photorealistic, " + QUALITY_FACADE, 0.62),
        ("d", "seamless tileable downtown mixed-use facade with beige limestone base "
              "rows and dark aluminum window frames, photorealistic, " + QUALITY_FACADE, 0.72),
    ],
    "desert": [
        ("a", "seamless tileable sandstone building facade with small deep-set windows, "
              "warm sand-colored stone, photorealistic, " + QUALITY_FACADE, 0.85),
        ("b", "seamless tileable adobe desert hotel facade, smooth earth-toned plaster "
              "with wooden shutters, photorealistic, " + QUALITY_FACADE, 0.85),
        ("c", "seamless tileable whitewashed desert stucco facade with narrow arched "
              "windows and blue painted trim, photorealistic, " + QUALITY_FACADE, 0.83),
        ("d", "seamless tileable modern red sandstone office facade with horizontal "
              "window bands, photorealistic, " + QUALITY_FACADE, 0.7),
    ],
    "alpine": [
        ("a", "seamless tileable grey stone mountain hotel facade with warm lit "
              "windows and dark timber frames, photorealistic, " + QUALITY_FACADE, 0.75),
        ("b", "seamless tileable concrete alpine building facade, minimalist grey "
              "panels with narrow windows, photorealistic, " + QUALITY_FACADE, 0.7),
        ("c", "seamless tileable alpine chalet timber facade, honey wooden planks "
              "with small windows and carved balcony rail, photorealistic, "
              + QUALITY_FACADE, 0.8),
        ("d", "seamless tileable modern glass and dark stone alpine hotel facade, "
              "photorealistic, " + QUALITY_FACADE, 0.55),
    ],
    "coast": [
        ("a", "seamless tileable white stucco seaside hotel facade with blue shutters "
              "and small balconies, photorealistic, " + QUALITY_FACADE, 0.75),
        ("b", "seamless tileable pastel mediterranean apartment facade, cream and "
              "terracotta stripes with arched windows, photorealistic, " + QUALITY_FACADE, 0.75),
        ("c", "seamless tileable weathered pastel pink villa facade with white "
              "shutters and wrought iron balconies, photorealistic, " + QUALITY_FACADE, 0.78),
        ("d", "seamless tileable modern seaside white concrete facade with large glass "
              "windows and vertical wooden slats, photorealistic, " + QUALITY_FACADE, 0.6),
    ],
    "canyon": [
        ("a", "seamless tileable carved sandstone cliff-dwelling facade, warm red rock "
              "with small square windows and timber lintels, photorealistic, "
              + QUALITY_FACADE, 0.88),
        ("b", "seamless tileable weathered desert adobe facade, sun-bleached earth "
              "plaster with wooden shutters and cracked stucco, photorealistic, "
              + QUALITY_FACADE, 0.86),
        ("c", "seamless tileable rustic desert lodge facade, stacked stone and "
              "weathered timber with small deep windows, photorealistic, "
              + QUALITY_FACADE, 0.84),
        ("d", "seamless tileable sun-bleached stacked sandstone block facade with "
              "narrow windows, photorealistic, " + QUALITY_FACADE, 0.87),
    ],
    "sakura": [
        ("a", "seamless tileable traditional japanese machiya wooden facade, dark "
              "timber lattice and white plaster with grey tiled roof trim, "
              "photorealistic, " + QUALITY_FACADE, 0.78),
        ("b", "seamless tileable modern light stucco apartment facade with dark timber "
              "accents and narrow windows, photorealistic, " + QUALITY_FACADE, 0.74),
        ("c", "seamless tileable japanese modern shoji style facade, white plaster and "
              "dark timber grid with paper panels, photorealistic, " + QUALITY_FACADE, 0.72),
        ("d", "seamless tileable pastel japanese apartment facade with tiled windows "
              "and slim balcony rails, photorealistic, " + QUALITY_FACADE, 0.73),
    ],
    "volcano": [
        ("a", "seamless tileable dark volcanic stone fortress facade, black basalt "
              "blocks with narrow slit windows, photorealistic, " + QUALITY_FACADE, 0.82),
        ("b", "seamless tileable blackened concrete and obsidian panel facade, dark "
              "grey with faint ember cracks around windows, photorealistic, "
              + QUALITY_FACADE, 0.72),
        ("c", "seamless tileable dark obsidian and basalt building facade with glowing "
              "ember cracks, photorealistic, " + QUALITY_FACADE, 0.78),
        ("d", "seamless tileable charred timber and black stone facade with narrow "
              "windows, photorealistic, " + QUALITY_FACADE, 0.8),
    ],
}


def api(route: str, payload: dict, timeout: int = 900) -> dict:
    req = urllib.request.Request(
        HOST + route, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def wait_backend(session: str, timeout_s: int = 240) -> None:
    """Wait until the ComfyUI backend reports running."""
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
        time.sleep(10)
    raise RuntimeError("backend did not reach running state")


def warmup(session: str) -> None:
    """Tiny generation to force model load before real work."""
    payload = {
        "session_id": session, "images": 1, "model": MODEL,
        "prompt": "grey texture", "negativeprompt": "",
        "width": 256, "height": 256, "steps": 4, "cfg_scale": max(CFG, 1.0), "seed": 3,
    }
    resp = api("/API/GenerateText2Image", payload)
    if "images" not in resp:
        raise RuntimeError("warmup failed: " + json.dumps(resp)[:200])
    print("warmup: ok")


def detrend(img: Image.Image, sigma_frac: float = 0.15) -> Image.Image:
    """Remove slow luminance gradients (baked shading/banding) without touching hue.

    Subtracts a heavily blurred copy of luminance and re-adds its mean, so the
    macro brightness is flattened edge to edge but colour is preserved.
    """
    a = np.asarray(img).astype(np.float64)
    h = a.shape[0]
    lum = a.mean(axis=2)
    lum8 = np.clip(lum, 0, 255).astype(np.uint8)
    low = np.asarray(Image.fromarray(lum8).filter(
        ImageFilter.GaussianBlur(max(8.0, h * sigma_frac)))).astype(np.float64)
    out = a - (low - low.mean())[..., None]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def _wrap_blend(b: np.ndarray, feather: float) -> np.ndarray:
    """Blend the outer feather band with the half-rolled copy so the wrap edge
    joins the interior (no step, no detail flattening)."""
    h, w = b.shape[:2]
    fx = max(24.0, feather * w)
    fy = max(24.0, feather * h)
    px = np.arange(w)
    tw = np.clip(px / fx, 0.0, 1.0) * np.clip((w - 1 - px) / fx, 0.0, 1.0)
    bx = b * tw[None, :, None] + np.roll(b, w // 2, axis=1) * (1.0 - tw)[None, :, None]
    py = np.arange(h)
    th = np.clip(py / fy, 0.0, 1.0) * np.clip((h - 1 - py) / fy, 0.0, 1.0)
    out = bx * th[:, None, None] + np.roll(bx, h // 2, axis=0) * (1.0 - th)[:, None, None]
    return out


def make_seamless(img: Image.Image, feather: float = 0.10) -> Image.Image:
    """Seamless by construction: replace the low-frequency band with its periodic
    (FFT) version, keep the un-flattened high-frequency detail, then wrap-blend
    the thin edge band with the interior. No visible cross, no edge banding."""
    a = np.asarray(img).astype(np.float64)
    h, w = a.shape[:2]
    F = np.fft.fft2(a, axes=(0, 1))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    freq = np.sqrt(fx * fx + fy * fy)
    low_mask = np.exp(-((freq / 0.010) ** 2))
    low = np.fft.ifft2(F * low_mask[..., None], axes=(0, 1)).real
    blur = np.asarray(img.filter(ImageFilter.GaussianBlur(max(6.0, w * 0.03)))).astype(np.float64)
    detail = a - blur
    out = _wrap_blend(low + detail, feather)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def sharpen_resize(img: Image.Image, size: int = OUT_SIZE) -> Image.Image:
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return img.filter(ImageFilter.UnsharpMask(radius=1.3, percent=55, threshold=3))


def _resize_normal(nm: np.ndarray, size: int) -> np.ndarray:
    v = (nm.astype(np.float32) / 255.0) * 2.0 - 1.0
    enc = np.clip((v * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    enc = np.asarray(Image.fromarray(enc).resize((size, size), Image.LANCZOS))
    v = (enc.astype(np.float32) / 255.0) * 2.0 - 1.0
    v[..., 2] = np.maximum(v[..., 2], 1e-3)
    v /= np.linalg.norm(v, axis=-1, keepdims=True)
    return np.clip((v * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)


def generate(prompt: str, seed: int, size: int = GEN_SIZE,
             negative: str = NEG) -> Image.Image:
    session = api("/API/GetNewSession", {})["session_id"]
    payload = {
        "session_id": session,
        "images": 1,
        "model": MODEL,
        "prompt": prompt,
        "negativeprompt": negative if CFG > 1.1 else "",
        "width": size,
        "height": size,
        "steps": STEPS,
        "cfg_scale": CFG,
        "seed": seed,
    }
    resp = api("/API/GenerateText2Image", payload)
    if "images" not in resp:
        print("API error: " + json.dumps(resp)[:300])
        return None
    img_path = resp["images"][0]
    if isinstance(img_path, dict):
        img_path = img_path["image"]
    with urllib.request.urlopen(f"{HOST}/{quote(img_path)}", timeout=120) as r:
        img = Image.open(io.BytesIO(r.read())).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    return img


def tile_score(img: Image.Image) -> float:
    """Prefer flat seams (edge step <= internal step) and rich micro detail."""
    a = np.asarray(img.convert("L")).astype(np.float64)
    edge = max(np.abs(a[:, 0] - a[:, -1]).mean(), np.abs(a[0, :] - a[-1, :]).mean())
    internal = max(np.abs(np.diff(a, axis=1)).mean(), np.abs(np.diff(a, axis=0)).mean())
    hp = a - np.asarray(Image.fromarray(a.astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(3))).astype(np.float64)
    return hp.std() * 2.0 - max(0.0, edge - internal) * 8.0


def best_of(prompt: str, seed0: int, feather: float, detrend_frac: float,
            negative: str = NEG, size: int = GEN_SIZE):
    """Generate BEST_OF candidates, return (raw_high_res, chosen_seed, score)."""
    best = None
    for i in range(BEST_OF):
        seed = seed0 + i * 101
        img = generate(prompt, seed, size, negative)
        if img is None:
            continue
        img = detrend(img, detrend_frac)
        img = make_seamless(img, feather)
        sc = tile_score(img)
        print(f"    candidate seed={seed} score={sc:.2f}")
        if best is None or sc > best[2]:
            best = (img, seed, sc)
    return best


def derivatives(spec: dict, hi_albedo: Image.Image, albedo: Image.Image,
                out: str, name: str) -> None:
    lum = np.asarray(hi_albedo.convert("L")).astype(np.float64) / 255.0
    nm = normal_map(lum, strength=spec["normal_strength"])
    save_png(f"{out}/{name}_normal.png", _resize_normal(nm, OUT_SIZE))
    lum2 = np.asarray(albedo.convert("L")).astype(np.float64) / 255.0
    base_r = spec["rough"]
    rough = np.clip(base_r + 0.08 * (0.5 - lum2), 0.05, 1.0)
    ao = np.clip(0.7 + 0.3 * lum2, 0.0, 1.0)
    metal = np.zeros_like(lum2)
    save_png(f"{out}/{name}_orm.png", orm_map(ao, rough, metal))
    write_license(f"{out}/{name}_normal.png.license", f"{name}_normal.png",
                  "procedural (tools/assetgen/gen_sdxl_tex.py)",
                  "normal derived from high-res Z-Image albedo luminance (wrap gradient)")
    write_license(f"{out}/{name}_orm.png.license", f"{name}_orm.png",
                  "procedural (tools/assetgen/gen_sdxl_tex.py)",
                  "roughness/ao derived from albedo; non-metallic")


def gen_facade(biome: str, suffix: str, prompt: str, rough: float, force: bool) -> None:
    out = asset_path(f"environments/{biome}")
    albedo_path = f"{out}/facade_{suffix}.webp"
    if os.path.exists(albedo_path) and not force:
        print(f"facade {biome}/{suffix}: exists, skip")
        return
    seed0 = SEED_BASE + zlib.crc32(f"facade/{biome}/{suffix}".encode()) % 10000
    best = best_of(prompt, seed0, feather=0.06, detrend_frac=0.15,
                   negative=NEG + FACADE_NEG_EXTRA, size=GEN_SIZE)
    if best is None:
        print(f"facade {biome}/{suffix}: FAILED")
        return
    hi, seed, sc = best
    img = sharpen_resize(hi)
    img.save(albedo_path, quality=92)
    write_license(f"{albedo_path}.license", f"facade_{suffix}.webp",
                  "SwarmUI Z-Image Turbo + offset-heal seamless",
                  f"seed: {seed}; score: {sc:.2f}; prompt: {prompt}")
    spec = {"normal_strength": 1.4, "rough": rough}
    derivatives(spec, hi, img, out, f"facade_{suffix}")
    print(f"facade {biome}/{suffix}: done")


def gen_facade_emissions(biome: str) -> None:
    out = asset_path(f"environments/{biome}")
    palette = np.array([
        [1.00, 0.64, 0.28],
        [0.24, 0.72, 1.00],
        [1.00, 0.26, 0.16],
        [0.38, 1.00, 0.68],
    ])
    for suffix, _prompt, _rough in FACADES.get(biome, []):
        albedo_path = f"{out}/facade_{suffix}.webp"
        emission_path = f"{out}/facade_{suffix}_emission.webp"
        if not os.path.exists(albedo_path):
            print(f"facade emission {biome}/{suffix}: missing albedo")
            continue
        if os.path.exists(emission_path):
            print(f"facade emission {biome}/{suffix}: exists, skip")
            continue
        rng = np.random.default_rng(SEED_BASE + zlib.crc32(f"emission/{biome}/{suffix}".encode()))
        albedo = Image.open(albedo_path).convert("L")
        lum = np.asarray(albedo).astype(np.float64) / 255.0
        local = np.asarray(albedo.filter(ImageFilter.GaussianBlur(7))).astype(np.float64) / 255.0
        mask = np.clip((local - lum - 0.018) * 8.5, 0.0, 1.0)
        mask *= np.clip((0.60 - local) / 0.22, 0.0, 1.0)
        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(1.2))).astype(np.float64) / 255.0
        low, high = np.percentile(mask, [42, 92])
        mask = np.clip((mask - low) / max(high - low, 0.001), 0.0, 1.0)
        field = (rng.random((10, 16)) < 0.48).astype(np.uint8) * 255
        field = np.asarray(Image.fromarray(field).resize(albedo.size, Image.Resampling.NEAREST)).astype(np.float64) / 255.0
        mask *= field
        glow = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(5))).astype(np.float64) / 255.0
        zone = np.minimum((np.arange(albedo.size[0]) * len(palette) // albedo.size[0]), len(palette) - 1)
        colors = np.repeat(palette[zone][None, :, :], albedo.size[0], axis=0)
        emission = (mask[..., None] * 1.75 + glow[..., None] * 0.22) * colors
        save_webp(emission_path, np.clip(emission, 0.0, 1.0))
        write_license(emission_path + ".license", f"facade_{suffix}_emission.webp",
                      "procedural (tools/assetgen/gen_sdxl_tex.py)",
                      "window mask derived from facade albedo luminance with deterministic light zones")
        print(f"facade emission {biome}/{suffix}: done")


def main() -> None:
    argv = sys.argv[1:]
    force = "--force" in argv or os.environ.get("FORCE") == "1"
    argv = [a for a in argv if a != "--force"]
    if "city_emission" in argv:
        gen_facade_emissions("city")
        return
    want_all = (not argv) or "all" in argv
    want_facades = want_all or "facades" in argv or any(
        k.endswith("_facade") or k.endswith("_facades") for k in argv)
    facade_biomes = []
    for k in argv:
        if k.endswith("_facades"):
            facade_biomes.append(k[:-8])
        elif k.endswith("_facade"):
            facade_biomes.append(k[:-7])
    if not facade_biomes:
        facade_biomes = list(FACADES)
    keys = [k for k in argv if k in SPECS]
    if want_all:
        keys = list(SPECS)
    warmed = False
    for key in keys:
        spec = SPECS[key]
        out = asset_path(f"environments/{key.rsplit('_', 1)[0]}/"
                         + ("road" if key.endswith("_road") else "terrain"))
        os.makedirs(out, exist_ok=True)
        name = "asphalt" if key.endswith("_road") else "surface"
        albedo_path = f"{out}/{name}_albedo.webp"
        if os.path.exists(albedo_path) and not force:
            print(f"{key}: already exists, skip (use --force to regenerate)")
            continue
        if not warmed:
            session = api("/API/GetNewSession", {})["session_id"]
            wait_backend(session)
            warmup(session)
            warmed = True
        print(f"{key}: generating...")
        seed0 = SEED_BASE + zlib.crc32(key.encode()) % 10000
        feather = 0.10 if key.endswith("_road") else 0.12
        detrend_frac = 0.18 if key.endswith("_road") else 0.22
        neg_extra = (ROAD_NEG_EXTRA if key.endswith("_road") else TERRAIN_NEG_EXTRA)
        neg_extra += KEY_NEG_EXTRA.get(key, "")
        best = best_of(spec["prompt"], seed0, feather, detrend_frac,
                       negative=NEG + neg_extra)
        if best is None:
            print(f"{key}: FAILED")
            continue
        hi, seed, sc = best
        img = sharpen_resize(hi)
        img.save(albedo_path, quality=92)
        write_license(f"{albedo_path}.license", f"{name}_albedo.webp",
                      "SwarmUI Z-Image Turbo + offset-heal seamless",
                      f"seed: {seed}; score: {sc:.2f}; prompt: {spec['prompt']}")
        derivatives(spec, hi, img, out, name)
        arr8 = np.asarray(img).astype(np.int32)
        edge = int(max(np.abs(arr8[:, 0] - arr8[:, -1]).max(),
                       np.abs(arr8[0, :] - arr8[-1, :]).max()))
        internal = int(max(np.abs(np.diff(arr8, axis=1)).max(),
                           np.abs(np.diff(arr8, axis=0)).max()))
        note = "ok" if edge <= internal + 8 else f"WARN seam {edge} vs {internal}"
        print(f"{key}: done ({note})")
    if want_facades:
        for biome, facades in FACADES.items():
            if biome not in facade_biomes:
                continue
            if not warmed:
                session = api("/API/GetNewSession", {})["session_id"]
                wait_backend(session)
                warmup(session)
                warmed = True
            for suffix, prompt, rough in facades:
                gen_facade(biome, suffix, prompt, rough, force)


if __name__ == "__main__":
    main()
