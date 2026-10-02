#!/usr/bin/env python3
"""Alpine and coastal biome PBR sets + skies.

Outputs into assets/environments/:
  alpine/terrain/surface_*      (snow)
  alpine/road/asphalt_*         (cold dark asphalt)
  alpine/sky.hdr                (pale cold noon)
  coast/terrain/surface_*       (dry grass / sand mix)
  coast/road/asphalt_*          (light warm asphalt)
  coast/sky.hdr                 (vivid seaside noon)
"""

import numpy as np

from gen_sky import render, save_hdr, TOOL as SKY_TOOL
from pbr_common import (
    anisotropic_noise,
    asset_path,
    fbm,
    normal_map,
    orm_map,
    periodic_blur3,
    save_png,
    save_webp,
    seam_check,
    write_license,
)

SIZE = 1024
TOOL = "procedural synthesis (tools/assetgen/gen_biomes.py)"


def sealife(prefix: str, out: str, albedo: np.ndarray, height: np.ndarray,
            ao: np.ndarray, rough: np.ndarray, road: bool) -> None:
    albedo8 = (np.clip(albedo, 0, 1) * 255).astype(np.uint8)
    normal8 = normal_map(height, strength=2.2 if road else 1.5)
    orm8 = orm_map(ao, rough)
    kind = "road" if road else "terrain"
    name = "asphalt" if road else "surface"
    save_webp(f"{out}/{name}_albedo.webp", albedo)
    save_png(f"{out}/{name}_normal.png", normal8)
    save_png(f"{out}/{name}_orm.png", orm8)
    write_license(f"{out}/{name}_albedo.webp.license", f"{name}_albedo.webp", TOOL, f"{prefix} albedo")
    write_license(f"{out}/{name}_normal.png.license", f"{name}_normal.png", TOOL, f"{prefix} normal")
    write_license(f"{out}/{name}_orm.png.license", f"{name}_orm.png", TOOL, f"{prefix} ORM")
    for nm, arr in (("albedo", albedo8), ("normal", normal8), ("orm", orm8)):
        edge, internal = seam_check(arr)
        assert edge <= internal, f"{prefix}/{nm}: seam step {edge} > internal {internal}"


def alpine() -> None:
    # --- snow terrain
    drifts = fbm(SIZE, beta=2.2, seed=501)
    sparkle = fbm(SIZE, beta=0.05, seed=502)
    tracks = anisotropic_noise(SIZE, kx=18, ky=6, seed=503)
    height = 0.6 * drifts + 0.25 * tracks + 0.15 * sparkle
    t = drifts[..., None]
    albedo = np.array([0.88, 0.91, 0.97]) * (0.82 + 0.18 * t) - 0.06 * sparkle[..., None] * np.array([0.4, 0.5, 1.0])
    albedo = np.clip(albedo, 0.0, 1.0)
    ao = np.clip(0.82 + 0.18 * drifts, 0.0, 1.0)
    rough = 0.55 + 0.15 * sparkle  # snow is semi-glossy
    sealife("alpine snow", asset_path("environments/alpine/terrain"), albedo, height, ao, rough, road=False)

    # --- cold asphalt with salt patches
    base = fbm(SIZE, beta=1.8, seed=511)
    grain = fbm(SIZE, beta=0.2, seed=512)
    stones = periodic_blur3(
        (np.random.default_rng(513).random((SIZE, SIZE)) > 0.98).astype(np.float64)
    )
    salt = fbm(SIZE, beta=2.6, seed=514)
    height = 0.6 * base + 0.25 * grain + 0.15 * stones
    albedo = 0.17 + 0.05 * base + 0.04 * grain + 0.14 * stones + 0.09 * salt
    albedo = np.clip(albedo, 0.0, 1.0)
    albedo = np.stack([albedo * 0.92, albedo * 0.97, albedo * 1.05], axis=-1)
    ao = np.clip(1.0 - 0.3 * (1.0 - base) * stones, 0.0, 1.0)
    rough = 0.85 + 0.08 * (grain - 0.5)
    sealife("alpine asphalt", asset_path("environments/alpine/road"), albedo, height, ao, rough, road=True)

    alpine_sky()
    print("alpine: ok")


def alpine_sky() -> None:
    sky = render({
        "zenith": np.array([0.20, 0.40, 0.85]),
        "horizon": np.array([0.84, 0.91, 1.00]),
        "ground": np.array([0.55, 0.60, 0.70]),
        "sun_tint": np.array([1.00, 0.97, 0.88]),
        "sun_elev": np.deg2rad(48.0),
        "sun_azim": np.deg2rad(205.0),
        "sun_power": 26.0,
    })
    out = asset_path("environments/alpine/sky.hdr")
    save_hdr(out, sky)
    write_license(out + ".license", "sky.hdr", SKY_TOOL, "alpine cold noon palette")
    print("alpine sky: ok")


def coast() -> None:
    # --- dry grass / sand mix
    patches = fbm(SIZE, beta=2.4, seed=601)
    blades = anisotropic_noise(SIZE, kx=20, ky=6, seed=602)
    grains = fbm(SIZE, beta=0.15, seed=603)
    height = 0.45 * blades + 0.35 * patches + 0.20 * grains
    grass = np.array([0.45, 0.50, 0.20])
    sand = np.array([0.85, 0.76, 0.55])
    t = np.clip(patches * 1.4 - 0.2, 0.0, 1.0)[..., None]
    albedo = grass * (1.0 - t) + sand * t
    albedo = np.clip(albedo * (0.85 + 0.25 * blades)[..., None], 0.0, 1.0)
    ao = np.clip(0.78 + 0.22 * patches, 0.0, 1.0)
    rough = 0.80 + 0.08 * (grains - 0.5)
    sealife("coast terrain", asset_path("environments/coast/terrain"), albedo, height, ao, rough, road=False)

    # --- light warm asphalt
    base = fbm(SIZE, beta=1.8, seed=611)
    grain = fbm(SIZE, beta=0.2, seed=612)
    stones = periodic_blur3(
        (np.random.default_rng(613).random((SIZE, SIZE)) > 0.98).astype(np.float64)
    )
    height = 0.6 * base + 0.25 * grain + 0.15 * stones
    albedo = np.stack([
        0.34 + 0.06 * base + 0.14 * stones + 0.03 * grain,
        0.33 + 0.06 * base + 0.14 * stones + 0.03 * grain,
        0.30 + 0.06 * base + 0.14 * stones + 0.03 * grain,
    ], axis=-1)
    albedo = np.clip(albedo, 0.0, 1.0)
    ao = np.clip(1.0 - 0.3 * (1.0 - base) * stones, 0.0, 1.0)
    rough = 0.88 + 0.05 * (grain - 0.5)
    sealife("coast asphalt", asset_path("environments/coast/road"), albedo, height, ao, rough, road=True)

    coast_sky()
    print("coast: ok")


def coast_sky() -> None:
    sky = render({
        "zenith": np.array([0.10, 0.34, 0.82]),
        "horizon": np.array([0.74, 0.88, 1.00]),
        "ground": np.array([0.45, 0.55, 0.60]),
        "sun_tint": np.array([1.00, 0.95, 0.80]),
        "sun_elev": np.deg2rad(55.0),
        "sun_azim": np.deg2rad(215.0),
        "sun_power": 28.0,
    })
    out = asset_path("environments/coast/sky.hdr")
    save_hdr(out, sky)
    write_license(out + ".license", "sky.hdr", SKY_TOOL, "coast vivid noon palette")
    print("coast sky: ok")


if __name__ == "__main__":
    import sys
    if "--sky" in sys.argv:
        # skies only: never touch the Z-Image terrain / procedural roads
        alpine_sky()
        coast_sky()
    else:
        alpine()
        coast()
