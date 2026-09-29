#!/usr/bin/env python3
"""Seamless asphalt PBR set for the city biome road.

Outputs into assets/environments/city/road/:
  asphalt_albedo.webp (1024^2, sRGB)
  asphalt_normal.png  (1024^2, linear, OpenGL Y+)
  asphalt_orm.png     (1024^2, linear, R=AO G=roughness B=metallic)
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


def main() -> None:
    base = fbm(SIZE, beta=1.8, seed=11)          # uneven surface patches
    grain = fbm(SIZE, beta=0.2, seed=22)         # fine grain
    stones = speckle(SIZE, density=0.02, seed=33)

    # --- height: base undulation + grain + stones (cavities around them)
    height = 0.6 * base + 0.25 * grain + 0.15 * stones

    # --- albedo: mid-gray asphalt, lighter aggregate dots, darker patches
    albedo = 0.20 + 0.06 * base + 0.04 * grain
    albedo += 0.16 * stones                      # light aggregate
    albedo -= 0.05 * fbm(SIZE, beta=3.5, seed=44)  # oil/dirt stains

    # --- ORM
    ao = np.clip(1.0 - 0.35 * (1.0 - base) * stones, 0.0, 1.0)
    rough = 0.93 + 0.05 * (grain - 0.5) - 0.08 * fbm(SIZE, beta=2.5, seed=55)
    metal = np.full((SIZE, SIZE), 0.0)

    albedo_p = np.clip(albedo, 0.0, 1.0)
    out = asset_path("environments/city/road")
    save_webp(f"{out}/asphalt_albedo.webp", albedo_p)
    save_png(f"{out}/asphalt_normal.png", normal_map(height, strength=2.5))
    save_png(f"{out}/asphalt_orm.png", orm_map(ao, rough, metal))
    write_license(
        f"{out}/asphalt_albedo.webp.license", "asphalt_albedo.webp", TOOL,
        "seamless fBm asphalt, aggregate speckle",
    )
    write_license(
        f"{out}/asphalt_normal.png.license", "asphalt_normal.png", TOOL,
        "derived from procedural height (wrap gradient)",
    )
    write_license(
        f"{out}/asphalt_orm.png.license", "asphalt_orm.png", TOOL,
        "AO from height, roughness 0.85-0.98, non-metallic",
    )

    # acceptance: edge step no larger than any internal step (true tiling)
    for name, arr in (
        ("albedo", (albedo_p * 255).astype(np.uint8)),
        ("normal", normal_map(height, strength=2.5)),
        ("orm", orm_map(ao, rough, metal)),
    ):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{name}: seam step {edge} > internal {internal}"
    print("gen_road: ok (seamless)")


if __name__ == "__main__":
    main()
