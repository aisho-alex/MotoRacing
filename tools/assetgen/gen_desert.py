#!/usr/bin/env python3
"""Desert biome PBR set: sand terrain, sun-bleached asphalt, dusk sky.

Outputs into assets/environments/desert/:
  terrain/surface_{albedo.webp,normal.png,orm.png}
  road/asphalt_{albedo.webp,normal.png,orm.png}
  sky.hdr
"""

import numpy as np

from gen_sky import TOOL as SKY_TOOL, render, save_hdr
from pbr_common import (
    DATE,
    anisotropic_noise,
    asset_path,
    fbm,
    normal_map,
    orm_map,
    save_png,
    save_webp,
    seam_check,
    write_license,
)
from pbr_common import periodic_blur3

SIZE = 1024
TOOL = "procedural synthesis (tools/assetgen/gen_desert.py)"

SAND_LIGHT = np.array([0.84, 0.74, 0.50])
SAND_DARK = np.array([0.66, 0.54, 0.34])
DUSK = {
    "zenith": np.array([0.16, 0.17, 0.40]),
    "horizon": np.array([0.98, 0.58, 0.30]),
    "ground": np.array([0.28, 0.19, 0.12]),
    "sun_tint": np.array([1.05, 0.72, 0.42]),
    "sun_elev": np.deg2rad(11.0),
    "sun_azim": np.deg2rad(200.0),
    "sun_power": 30.0,
}


def sand() -> None:
    ripples = anisotropic_noise(SIZE, kx=4, ky=22, seed=301)   # dune ripples
    patches = fbm(SIZE, beta=2.4, seed=302)
    grains = fbm(SIZE, beta=0.15, seed=303)
    pebbles = periodic_blur3(
        (np.random.default_rng(304).random((SIZE, SIZE)) > 0.995).astype(np.float64)
    )

    height = 0.5 * ripples + 0.3 * patches + 0.15 * grains + 0.05 * pebbles

    t = patches[..., None]
    albedo = SAND_DARK * (1.0 - t) + SAND_LIGHT * t
    albedo = albedo * (0.9 + 0.2 * grains)[..., None]
    albedo = np.clip(albedo, 0.0, 1.0)

    ao = np.clip(0.8 + 0.2 * ripples, 0.0, 1.0)
    rough = 0.82 + 0.08 * (grains - 0.5)

    out = asset_path("environments/desert/terrain")
    albedo8 = (albedo * 255).astype(np.uint8)
    normal8 = normal_map(height, strength=1.4)
    orm8 = orm_map(ao, rough)
    save_webp(f"{out}/surface_albedo.webp", albedo)
    save_png(f"{out}/surface_normal.png", normal8)
    save_png(f"{out}/surface_orm.png", orm8)
    for f, note in (
        ("surface_albedo.webp.license", "sand: ripples + patch mixing"),
        ("surface_normal.png.license", "derived from dune ripple height"),
        ("surface_orm.png.license", "AO from ripples, roughness ~0.82"),
    ):
        write_license(f"{out}/{f}", f.split(".license")[0], TOOL, note)
    for name, arr in (("albedo", albedo8), ("normal", normal8), ("orm", orm8)):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{name}: seam step {edge} > internal {internal}"
    print("desert terrain: ok (seamless)")


def road() -> None:
    base = fbm(SIZE, beta=1.8, seed=311)
    grain = fbm(SIZE, beta=0.2, seed=312)
    stones = periodic_blur3(
        (np.random.default_rng(313).random((SIZE, SIZE)) > 0.98).astype(np.float64)
    )
    dust = fbm(SIZE, beta=2.8, seed=314)

    height = 0.6 * base + 0.25 * grain + 0.15 * stones
    # sun-bleached asphalt with warm dust tint
    albedo = 0.30 + 0.06 * base + 0.04 * grain + 0.16 * stones + 0.10 * dust
    albedo = np.clip(albedo, 0.0, 1.0)
    albedo = np.stack([albedo, albedo * 0.94, albedo * 0.82], axis=-1)

    ao = np.clip(1.0 - 0.35 * (1.0 - base) * stones, 0.0, 1.0)
    rough = 0.90 + 0.05 * (grain - 0.5)

    out = asset_path("environments/desert/road")
    albedo8 = (albedo * 255).astype(np.uint8)
    normal8 = normal_map(height, strength=2.5)
    orm8 = orm_map(ao, rough)
    save_webp(f"{out}/asphalt_albedo.webp", albedo)
    save_png(f"{out}/asphalt_normal.png", normal8)
    save_png(f"{out}/asphalt_orm.png", orm8)
    write_license(f"{out}/asphalt_albedo.webp.license", "asphalt_albedo.webp", TOOL,
                  "bleached asphalt + sand dust")
    write_license(f"{out}/asphalt_normal.png.license", "asphalt_normal.png", TOOL,
                  "wrap gradient of procedural height")
    write_license(f"{out}/asphalt_orm.png.license", "asphalt_orm.png", TOOL,
                  "AO/roughness as city, non-metallic")
    for name, arr in (("albedo", albedo8), ("normal", normal8), ("orm", orm8)):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{name}: seam step {edge} > internal {internal}"
    print("desert road: ok (seamless)")


def sky() -> None:
    rgb = render(DUSK)
    out = asset_path("environments/desert/sky.hdr")
    save_hdr(out, rgb)
    write_license(out + ".license", "sky.hdr", SKY_TOOL, "desert dusk palette")
    print(f"desert sky: ok (max={rgb.max():.1f})")


if __name__ == "__main__":
    sand()
    road()
    sky()
