#!/usr/bin/env python3
"""Seamless cel-style textures for the city lot props (mall / skatepark / plaza).

Reuses the SwarmUI Z-Image Turbo pipeline from gen_sdxl_tex.py (offset-heal
seamless + best-of-N + derived normal/ORM). Output is a flat-cel texture set per
material slot, written to assets/environments/city/buildings/tex/ and applied to
the GLBs by tools/assetgen/retexture_model.py.

Usage: python3 gen_model_tex.py all | mall_wall mall_glass ... --force
"""
import os
import sys
import zlib

import numpy as np

import gen_sdxl_tex as g
from pbr_common import seam_check

TEX_DIR = g.asset_path("environments/city/buildings/tex")
SEED_BASE = 9311

# name -> (style prefix, prompt, roughness, normal_strength)
SETS = {
    "mall_wall": (
        g.STYLE_FACADE,
        "seamless repeating modern shopping mall exterior facade, warm beige "
        "stone panels with a lower storefront band of large dark glass windows "
        "and simple signage strips, regular rows of upper floor windows, "
        "no perspective, no people, no sky, no street, no scene",
        0.72, 1.3,
    ),
    "mall_glass": (
        g.STYLE_FACADE,
        "seamless repeating modern shopping mall glass curtain wall, dark "
        "blue-green low-iron glass panels in a slim pale metal grid, subtle "
        "floor divisions, flat even lighting, no perspective, no people, no sky",
        0.35, 1.1,
    ),
    "skate_concrete": (
        g.STYLE_SURFACE,
        "smooth polished light grey concrete surface, fine aggregate speckle, "
        "faint scuff marks and a few hairline cracks, " + g.QUALITY,
        0.80, 1.4,
    ),
    "fountain_stone": (
        g.STYLE_SURFACE,
        "pale carved granite stone surface, fine grain speckle, subtle tooling "
        "marks, " + g.QUALITY,
        0.68, 1.3,
    ),
    "plaza_pavement": (
        g.STYLE_SURFACE,
        "large square paving slabs of light warm grey stone with thin darker "
        "joints, smooth clean surface, " + g.QUALITY,
        0.85, 1.5,
    ),
    "court_paint": (
        g.STYLE_SURFACE,
        "plain painted sports court surface, solid teal green painted asphalt "
        "with slight even wear, no lines, no markings, no grid, no objects, "
        + g.QUALITY,
        0.82, 1.1,
    ),
}


def gen_set(name: str, force: bool) -> None:
    style, prompt, rough, nstr = SETS[name]
    albedo_path = f"{TEX_DIR}/{name}.png"
    if os.path.exists(albedo_path) and not force:
        print(f"{name}: exists, skip")
        return
    os.makedirs(TEX_DIR, exist_ok=True)
    seed0 = SEED_BASE + zlib.crc32(name.encode()) % 10000
    # Facade slots want the front-elevation style; ground/prop slots the surface.
    is_facade = style == g.STYLE_FACADE
    neg = g.NEG + (g.FACADE_NEG_EXTRA if is_facade else g.TERRAIN_NEG_EXTRA)
    best = g.best_of(style + prompt, seed0,
                     feather=0.06 if is_facade else 0.10,
                     detrend_frac=0.15 if is_facade else 0.20,
                     negative=neg)
    if best is None:
        print(f"{name}: FAILED")
        return
    hi, seed, sc = best
    img = g.sharpen_resize(hi)
    img.save(albedo_path)
    g.write_license(
        albedo_path + ".license", f"{name}.png",
        "SwarmUI Z-Image Turbo + offset-heal seamless",
        f"seed: {seed}; score: {sc:.2f}; prompt: {prompt}")
    spec = {"normal_strength": nstr, "rough": rough}
    g.derivatives(spec, hi, img, TEX_DIR, name)
    edge, internal = seam_check(np.asarray(img))
    note = "ok" if edge <= internal + 8 else f"WARN seam {edge} vs {internal}"
    print(f"{name}: done ({note})")


def main() -> None:
    argv = sys.argv[1:]
    force = "--force" in argv or os.environ.get("FORCE") == "1"
    argv = [a for a in argv if a != "--force"]
    keys = list(SETS) if (not argv or "all" in argv) else [k for k in argv if k in SETS]
    warmed = False
    for key in keys:
        if not warmed:
            session = g.api("/API/GetNewSession", {})["session_id"]
            g.wait_backend(session)
            g.warmup(session)
            warmed = True
        gen_set(key, force)


if __name__ == "__main__":
    main()
