#!/usr/bin/env python3
"""Procedural equirectangular HDR skies (Radiance RGBE).

render(...) builds a sky from a palette + sun placement; `main` writes the
city noon sky. gen_desert.py imports render() for its dusk variant.
"""

import os

import numpy as np

from pbr_common import DATE, asset_path, write_license

W, H = 2048, 1024
TOOL = "procedural synthesis (tools/assetgen/gen_sky.py)"

CITY = {
    "zenith": np.array([0.06, 0.16, 0.55]),
    "horizon": np.array([0.93, 0.63, 0.40]),
    "ground": np.array([0.16, 0.15, 0.13]),
    "sun_tint": np.array([1.00, 0.85, 0.62]),
    "sun_elev": np.deg2rad(34.0),
    "sun_azim": np.deg2rad(215.0),
    "sun_power": 24.0,
}

CITY_NIGHT = {
    "zenith": np.array([0.004, 0.008, 0.026]),
    "horizon": np.array([0.12, 0.032, 0.012]),
    "ground": np.array([0.003, 0.004, 0.009]),
    "sun_tint": np.array([0.52, 0.68, 1.00]),
    "sun_elev": np.deg2rad(42.0),
    "sun_azim": np.deg2rad(215.0),
    "sun_power": 9.0,
}

# Extra biomes: analytic skies written by main() alongside the city one.
CANYON = {
    "zenith": np.array([0.12, 0.26, 0.62]),
    "horizon": np.array([0.92, 0.66, 0.40]),
    "ground": np.array([0.30, 0.18, 0.12]),
    "sun_tint": np.array([1.00, 0.88, 0.62]),
    "sun_elev": np.deg2rad(58.0),
    "sun_azim": np.deg2rad(200.0),
    "sun_power": 26.0,
}

SAKURA = {
    "zenith": np.array([0.18, 0.38, 0.80]),
    "horizon": np.array([0.96, 0.80, 0.82]),
    "ground": np.array([0.20, 0.24, 0.16]),
    "sun_tint": np.array([1.00, 0.92, 0.78]),
    "sun_elev": np.deg2rad(42.0),
    "sun_azim": np.deg2rad(210.0),
    "sun_power": 20.0,
}

VOLCANO = {
    "zenith": np.array([0.05, 0.05, 0.10]),
    "horizon": np.array([0.55, 0.14, 0.05]),
    "ground": np.array([0.05, 0.03, 0.03]),
    "sun_tint": np.array([1.00, 0.45, 0.22]),
    "sun_elev": np.deg2rad(8.0),
    "sun_azim": np.deg2rad(190.0),
    "sun_power": 30.0,
}

EXTRA_SKIES = {"canyon": CANYON, "sakura": SAKURA, "volcano": VOLCANO}


def render(palette: dict) -> np.ndarray:
    zenith = palette["zenith"]
    horizon = palette["horizon"]
    ground = palette["ground"]
    sun_tint = palette["sun_tint"]
    lon = (np.arange(W) + 0.5) / W * 2.0 * np.pi
    lat = np.pi / 2.0 - (np.arange(H) + 0.5) / H * np.pi  # +pi/2 top
    lon_g, lat_g = np.meshgrid(lon, lat)
    dx = np.cos(lat_g) * np.cos(lon_g)
    dy = np.sin(lat_g)
    dz = np.cos(lat_g) * np.sin(lon_g)

    elev, azim = palette["sun_elev"], palette["sun_azim"]
    sun = np.array([
        np.cos(elev) * np.cos(azim),
        np.sin(elev),
        np.cos(elev) * np.sin(azim),
    ])
    cos_sun = np.clip(dx * sun[0] + dy * sun[1] + dz * sun[2], -1.0, 1.0)

    up = dy
    # The chase camera looks slightly down, so almost all visible sky sits in
    # the first ~15 deg. Confine the warm horizon colour to a thin band and
    # smoothstep into a full saturated zenith dome above it.
    band = np.clip(up / 0.16, 0.0, 1.0)
    t = band * band * (3.0 - 2.0 * band)
    sky = horizon[None, None, :] * (1.0 - t[..., None]) + zenith[None, None, :] * t[..., None]

    below = np.clip(-up, 0.0, 1.0)
    ground_col = ground[None, None, :] * (1.0 - 0.6 * below[..., None]) + (
        horizon[None, None, :] * 0.25 * np.clip(1.0 - below * 4.0, 0.0, 1.0)[..., None]
    )

    rgb = np.where((up > 0)[..., None], sky, ground_col)

    # Tight halo: a broad soft term washed the whole sky toward white.
    glow = 0.15 * (np.clip(cos_sun, 0.0, 1.0) ** 18.0) + 1.1 * (np.clip(cos_sun, 0.0, 1.0) ** 350.0)
    rgb += glow[..., None] * sun_tint[None, None, :] * np.clip(up, 0.0, 1.0)[..., None]
    disc = (cos_sun > np.cos(np.deg2rad(1.2))).astype(np.float64)
    rgb += disc[..., None] * sun_tint[None, None, :] * palette["sun_power"]

    return np.clip(rgb, 0.0, None)


def save_hdr(path: str, rgb: np.ndarray) -> None:
    assert not np.isnan(rgb).any(), "NaN in sky"
    assert rgb.max() > 1.0, "sun disc missing"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n")
        f.write(b"-Y %d +X %d\n" % (H, W))
        f.write(_to_rgbe(rgb).tobytes())


def _to_rgbe(rgb: np.ndarray) -> np.ndarray:
    v = rgb.max(axis=-1)
    m, e = np.frexp(np.where(v > 0, v, 1.0))  # m in [0.5, 1)
    scale = np.where(v > 0, m * 256.0 / np.maximum(v, 1e-12), 0.0)
    r = np.clip(rgb[..., 0] * scale, 0, 255)
    g = np.clip(rgb[..., 1] * scale, 0, 255)
    b = np.clip(rgb[..., 2] * scale, 0, 255)
    ee = np.where(v > 0, e + 128, 0)
    return np.stack([r, g, b, ee], axis=-1).astype(np.uint8)


def main() -> None:
    # City tracks are day races (night_racing is off), so use the bright noon
    # palette. CITY_NIGHT stays available for a future night city.
    rgb = render(CITY)
    out = asset_path("environments/city/sky.hdr")
    save_hdr(out, rgb)
    write_license(out + ".license", "sky.hdr", TOOL, "analytic noon gradient + sun, RGBE")
    print(f"gen_sky: ok (max={rgb.max():.1f})")
    for biome, palette in EXTRA_SKIES.items():
        rgb = render(palette)
        out = asset_path(f"environments/{biome}/sky.hdr")
        save_hdr(out, rgb)
        write_license(out + ".license", "sky.hdr", TOOL,
                      "analytic gradient + sun, RGBE")
        print(f"{biome} sky: ok (max={rgb.max():.1f})")


if __name__ == "__main__":
    main()
