#!/usr/bin/env python3
"""Seamless flat-cartoon asphalt PBR sets for every biome road.

Procedural (no backend): a plain, slightly speckled tarmac tinted per biome
with a sparse accent (salt, petals, embers). Matches the cel-shaded actors.

Outputs per biome into assets/environments/<biome>/road/:
  asphalt_albedo.webp (1024^2, sRGB)
  asphalt_normal.png  (1024^2, linear, OpenGL Y+)
  asphalt_orm.png     (linear, R=ao G=roughness B=metallic)
"""

import numpy as np

from pbr_common import (
    asset_path,
    fbm,
    normal_map,
    orm_map,
    save_png,
    save_webp,
    seam_check,
    speckle,
    write_license,
)

SIZE = 1024
TOOL = "procedural synthesis (tools/assetgen/gen_road.py)"

# base: tarmac value; stone: light aggregate strength; tint: RGB multiplier;
# accent: sparse decoration (salt flecks / petals / embers).
ROADS = {
    "city":    {"base": 0.30, "stone": 0.12, "tint": (1.00, 1.00, 1.00)},
    "desert":  {"base": 0.42, "stone": 0.10, "tint": (1.02, 0.99, 0.92)},
    "alpine":  {"base": 0.26, "stone": 0.10, "tint": (0.95, 0.99, 1.08), "accent": "salt"},
    "coast":   {"base": 0.34, "stone": 0.11, "tint": (1.00, 0.99, 0.95)},
    "canyon":  {"base": 0.34, "stone": 0.10, "tint": (1.06, 1.00, 0.90)},
    "sakura":  {"base": 0.32, "stone": 0.11, "tint": (0.99, 0.98, 1.00), "accent": "petals"},
    "volcano": {"base": 0.10, "stone": 0.06, "tint": (1.00, 1.00, 1.00), "accent": "embers"},
}

ACCENT_COLORS = {
    "salt": (0.95, 0.97, 1.00),
    "petals": (1.00, 0.62, 0.78),
    "embers": (1.00, 0.45, 0.12),
}


def _road(biome: str, cfg: dict) -> None:
    base = fbm(SIZE, beta=1.8, seed=11 + len(biome))
    grain = fbm(SIZE, beta=0.2, seed=22 + len(biome))
    stones = speckle(SIZE, density=0.012, seed=33 + len(biome))
    stains = fbm(SIZE, beta=3.5, seed=44 + len(biome))

    # --- height: flat; just enough relief to catch the cel light
    height = 0.6 * base + 0.15 * grain + 0.10 * stones

    # --- albedo: bright, clean tarmac + light aggregate dots + faint stains
    val = cfg["base"] + 0.04 * base + 0.02 * grain
    val += cfg["stone"] * stones
    val -= 0.03 * stains
    albedo = np.clip(val, 0.0, 1.0)[..., None] * np.array(cfg["tint"])[None, None, :]

    accent = cfg.get("accent")
    if accent:
        mask = speckle(SIZE, density=0.006, seed=77 + len(biome))
        col = np.array(ACCENT_COLORS[accent])[None, None, :]
        albedo = albedo * (1.0 - mask[..., None]) + col * mask[..., None]

    # --- ORM
    ao = np.clip(1.0 - 0.18 * (1.0 - base) * stones, 0.0, 1.0)
    rough = 0.90 + 0.04 * (grain - 0.5) - 0.05 * fbm(SIZE, beta=2.5, seed=55 + len(biome))
    metal = np.full((SIZE, SIZE), 0.0)

    albedo_p = np.clip(albedo, 0.0, 1.0)
    out = asset_path(f"environments/{biome}/road")
    save_webp(f"{out}/asphalt_albedo.webp", albedo_p)
    nm = normal_map(height, strength=1.2)
    save_png(f"{out}/asphalt_normal.png", nm)
    orm = orm_map(ao, rough, metal)
    save_png(f"{out}/asphalt_orm.png", orm)
    note = f"flat-cartoon tarmac, tint {cfg['tint']}" + (
        f", accent {accent}" if accent else "")
    write_license(f"{out}/asphalt_albedo.webp.license", "asphalt_albedo.webp", TOOL, note)
    write_license(f"{out}/asphalt_normal.png.license", "asphalt_normal.png", TOOL,
                  "derived from procedural height (wrap gradient, strength 1.2)")
    write_license(f"{out}/asphalt_orm.png.license", "asphalt_orm.png", TOOL,
                  "AO from height, roughness ~0.85-0.95, non-metallic")

    for name, arr in (
        ("albedo", (albedo_p * 255).astype(np.uint8)),
        ("normal", nm),
        ("orm", orm),
    ):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{biome} {name}: seam step {edge} > internal {internal}"
    print(f"road {biome}: ok (seamless)")


def main() -> None:
    for biome, cfg in ROADS.items():
        _road(biome, cfg)
    print("gen_road: all ok")


if __name__ == "__main__":
    main()
