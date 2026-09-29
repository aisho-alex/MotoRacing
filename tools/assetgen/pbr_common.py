#!/usr/bin/env python3
"""Shared helpers for procedural PBR texture generation.

All noise is built in the frequency domain, so every texture is seamless
(periodic) by construction: tiling is exact, not approximated.
"""

import os

import cv2
import numpy as np

DATE = "2026-09-24"
PROJ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def asset_path(rel: str) -> str:
    return os.path.join(PROJ, "assets", rel)


def fbm(size: int, beta: float = 1.6, seed: int = 0) -> np.ndarray:
    """Seamless 1/f^beta noise in [0, 1] via FFT filtering of white noise."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    spec = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = f ** (-beta)
    amp /= amp.mean()
    out = np.fft.ifft2(spec * amp).real
    return normalize01(out)


def anisotropic_noise(size: int, kx: float, ky: float, seed: int = 0) -> np.ndarray:
    """Seamless noise stretched along one axis (streaks). kx/ky: falloff."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    spec = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    amp = np.exp(-((fx * kx) ** 2) - ((fy * ky) ** 2))
    out = np.fft.ifft2(spec * amp).real
    return normalize01(out)


def normalize01(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / max(hi - lo, 1e-9)


def wrap_gradient(h: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Central differences with wrap-around (keeps seams perfect)."""
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    return gx, gy


def normal_map(h: np.ndarray, strength: float = 3.0) -> np.ndarray:
    """OpenGL-style (Y up) tangent-space normal map, uint8 RGB."""
    gx, gy_down = wrap_gradient(h)
    nx = -gx * strength * h.shape[0]
    ny = gy_down * strength * h.shape[0]  # +y up in tangent space
    nz = np.ones_like(h)
    norm = np.sqrt(nx * nx + ny * ny + 1.0)
    rgb = np.stack([nx / norm, ny / norm, nz / norm], axis=-1) * 0.5 + 0.5
    return (np.clip(rgb, 0.0, 1.0) * 255.0).astype(np.uint8)


def orm_map(ao: np.ndarray, rough: np.ndarray, metal: np.ndarray | None = None) -> np.ndarray:
    """glTF-style ORM: R = AO, G = roughness, B = metallic. uint8 RGB."""
    m = np.zeros_like(ao) if metal is None else metal
    rgb = np.stack([np.clip(ao, 0, 1), np.clip(rough, 0, 1), np.clip(m, 0, 1)], axis=-1)
    return (rgb * 255.0).astype(np.uint8)


def periodic_blur3(img: np.ndarray) -> np.ndarray:
    """3x3 binomial blur with wrap-around edges (keeps seams exact)."""
    k = np.array([[1.0, 2, 1], [2, 4, 2], [1, 2, 1]])
    k /= k.sum()
    out = np.zeros_like(img, dtype=np.float64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out += k[dy + 1, dx + 1] * np.roll(np.roll(img, dy, axis=0), dx, axis=1)
    return out


def speckle(size: int, density: float, seed: int) -> np.ndarray:
    """Binary dot mask of aggregate stones, seamless (periodic placement)."""
    rng = np.random.default_rng(seed)
    dots = rng.random((size, size)) > (1.0 - density)
    # grow dots a little with a periodic blur so stones are 1-3 px
    return periodic_blur3(dots.astype(np.float64))


def seam_check(img: np.ndarray) -> tuple[int, int]:
    """(edge, internal): max step across the wrap edge vs max internal step.

    A periodic texture has x[0] adjacent to x[N-1], so the edge step must not
    exceed the largest internal step. Returns (edge_diff, internal_diff).
    """
    a = img.astype(np.int32)
    edge = int(max(
        np.abs(a[:, 0] - a[:, -1]).max(),
        np.abs(a[0, :] - a[-1, :]).max(),
    ))
    internal = int(max(
        np.abs(np.diff(a, axis=1)).max(),
        np.abs(np.diff(a, axis=0)).max(),
    ))
    return edge, internal


def save_webp(path: str, arr01: np.ndarray, quality: int = 90) -> None:
    from PIL import Image

    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray((np.clip(arr01, 0, 1) * 255).astype(np.uint8)).save(path, quality=quality)


def save_png(path: str, arr: np.ndarray) -> None:
    from PIL import Image

    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(arr).save(path)


def write_license(path: str, asset: str, tool: str, note: str) -> None:
    with open(path, "w") as f:
        f.write(
            f"asset: {asset}\ntool: {tool}\ndate: {DATE}\n"
            f"rights: own work, CC0 (procedural synthesis, no third-party input)\n"
            f"prompt: n/a (procedural)\nnote: {note}\n"
        )
