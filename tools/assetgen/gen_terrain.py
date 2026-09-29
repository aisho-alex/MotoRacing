#!/usr/bin/env python3
"""Seamless grass PBR set for the city biome terrain.

Outputs into assets/environments/city/terrain/:
  grass_albedo.webp (1024^2, sRGB)
  grass_normal.png  (1024^2, linear, OpenGL Y+)
  grass_orm.png     (1024^2, linear, R=AO G=roughness B=metallic)
"""

import numpy as np

from pbr_common import (
    asset_path,
    anisotropic_noise,
    fbm,
    normal_map,
    orm_map,
    save_png,
    save_webp,
    seam_check,
    write_license,
)

SIZE = 1024
TOOL = "procedural synthesis (tools/assetgen/gen_terrain.py)"

# base grass hues (sRGB 0..1)
GREEN_DARK = np.array([0.10, 0.20, 0.07])
GREEN_MID = np.array([0.16, 0.30, 0.10])
GREEN_DRY = np.array([0.28, 0.30, 0.12])


def main() -> None:
    patches = fbm(SIZE, beta=2.6, seed=101)          # dry/light patches
    blades_a = anisotropic_noise(SIZE, kx=26, ky=5, seed=102)   # streaks along x
    blades_b = anisotropic_noise(SIZE, kx=5, ky=26, seed=103)   # streaks along y
    detail = fbm(SIZE, beta=0.1, seed=104)           # per-blade sparkle

    # --- height drives normal (blades = ridges)
    height = 0.45 * blades_a + 0.35 * blades_b + 0.20 * detail

    # --- albedo: mix greens by patches, blades add light/shadow
    t = np.clip(patches * 1.3 - 0.15, 0.0, 1.0)[..., None]
    albedo = GREEN_MID * (1.0 - t) + GREEN_DRY * t
    shade = 0.75 + 0.5 * blades_a * blades_b + 0.15 * (detail - 0.5)
    albedo = albedo * shade[..., None]
    albedo = np.clip(albedo + (GREEN_DARK - GREEN_MID) * (0.3 * (1.0 - patches))[..., None], 0.0, 1.0)

    # --- ORM
    ao = np.clip(0.75 + 0.25 * patches, 0.0, 1.0)
    rough = 0.85 + 0.08 * (detail - 0.5)
    metal = np.zeros((SIZE, SIZE))

    out = asset_path("environments/city/terrain")
    albedo8 = (np.clip(albedo, 0, 1) * 255).astype(np.uint8)
    normal8 = normal_map(height, strength=1.8)
    orm8 = orm_map(ao, rough, metal)
    save_webp(f"{out}/grass_albedo.webp", albedo)
    save_png(f"{out}/grass_normal.png", normal8)
    save_png(f"{out}/grass_orm.png", orm8)
    write_license(
        f"{out}/grass_albedo.webp.license", "grass_albedo.webp", TOOL,
        "seamless grass: anisotropic blade streaks + patch mixing",
    )
    write_license(
        f"{out}/grass_normal.png.license", "grass_normal.png", TOOL,
        "derived from procedural blade height (wrap gradient)",
    )
    write_license(
        f"{out}/grass_orm.png.license", "grass_orm.png", TOOL,
        "AO from patches, roughness ~0.85, non-metallic",
    )

    for name, arr in (("albedo", albedo8), ("normal", normal8), ("orm", orm8)):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{name}: seam step {edge} > internal {internal}"
    print("gen_terrain: ok (seamless)")


if __name__ == "__main__":
    main()
