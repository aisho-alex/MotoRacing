#!/usr/bin/env python3
"""Normalize open-asset motorcycle GLBs for SimpleRacing (bike variant).

Differences from normalize_car.py:
- accepts multiple scene roots (many bike GLBs are multi-root)
- no corner-wheel assumption: keeps any node named wheel/tyre/tire that can be
  classified as front/rear and renames it to wheel_front / wheel_rear for
  RaceBike; every other wheel-ish name (steering, hubcaps) is broken.
- grounds the model (min world y == 0), centers x/z by bounds, optional rescale
- prints DIMS and an estimated forward axis so BikeDef.model_yaw can be set.

Usage: normalize_bike.py <in.glb> <out.glb> [target_length]
"""
import sys

import numpy as np
from pygltflib import GLTF2, Node

ROUGH = {
    "tire": 0.95, "tyre": 0.95, "wheel": 0.95, "body": 0.35, "glass": 0.08,
    "light": 0.25, "seat": 0.8, "chrome": 0.15, "metal": 0.35, "trim": 0.7,
}


def node_world(g, idx, parent=np.identity(4), out=None):
    if out is None:
        out = {}
    n = g.nodes[idx]
    if n.matrix:
        m = parent @ np.array(n.matrix, dtype=float).reshape(4, 4).T
    else:
        t = np.identity(4)
        if n.translation:
            t[:3, 3] = n.translation
        if n.rotation:
            x, y, z, w = n.rotation
            t[:3, :3] = _quat(x, y, z, w)
        if n.scale:
            t[:3, :3] = t[:3, :3] @ np.diag(n.scale)
        m = parent @ t
    out[idx] = m
    for c in n.children or []:
        node_world(g, c, m, out)
    return out


def _quat(x, y, z, w):
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def all_world(g):
    out = {}
    for r in g.scenes[g.scene].nodes:
        node_world(g, r, np.identity(4), out)
    return out


def bounds(g, world):
    mn = np.array([np.inf] * 3)
    mx = -mn
    for i, m in world.items():
        n = g.nodes[i]
        if n.mesh is None:
            continue
        for prim in g.meshes[n.mesh].primitives:
            a = g.accessors[prim.attributes.POSITION]
            for cx in (a.min[0], a.max[0]):
                for cy in (a.min[1], a.max[1]):
                    for cz in (a.min[2], a.max[2]):
                        v = m @ np.array([cx, cy, cz, 1.0])
                        mn = np.minimum(mn, v[:3])
                        mx = np.maximum(mx, v[:3])
    return mn, mx


def main():
    src, dst = sys.argv[1], sys.argv[2]
    g = GLTF2().load(src)
    world = all_world(g)

    # wheel node pass: classify front/rear, rename; break the rest
    def is_front(nm):
        low = nm.lower()
        return ("front" in low or low.endswith("_f") or low.endswith("f") and "wheel" in low
                or "f_tyre" in low or "frontwheel" in low)

    def is_rear(nm):
        low = nm.lower()
        return ("back" in low or "rear" in low or low.endswith("_b")
                or "b_tyre" in low or "backwheel" in low)

    kept = {}
    for i in world:
        nm = g.nodes[i].name or ""
        low = nm.lower()
        if not any(k in low for k in ("wheel", "tyre", "tire")):
            continue
        if "steer" in low or "handle" in low:
            g.nodes[i].name = nm + "_x"
            continue
        if is_front(nm):
            kept[i] = "wheel_front"
        elif is_rear(nm):
            kept[i] = "wheel_rear"
        # else leave; baked decorations named wheel are harmless if unnamed
    for i, name in kept.items():
        g.nodes[i].name = name
    print(f"wheel nodes renamed: {len(kept)}")

    mn, mx = bounds(g, world)
    scale = 1.0
    if len(sys.argv) > 3:
        target = float(sys.argv[3])
        horiz = max(mx[0] - mn[0], mx[2] - mn[2])
        scale = target / horiz
    shift = [-scale * (mn[0] + mx[0]) / 2.0, -scale * mn[1], -scale * (mn[2] + mx[2]) / 2.0]

    old_roots = list(g.scenes[g.scene].nodes)
    new_root = Node()
    new_root.children = old_roots
    new_root.translation = shift
    new_root.scale = [scale] * 3
    g.nodes.append(new_root)
    g.scenes[g.scene].nodes = [len(g.nodes) - 1]

    # forward estimate: long axis, "taller end is front" heuristic
    world2 = all_world(g)
    mn2, mx2 = bounds(g, world2)
    ext = mx2 - mn2
    axis = 0 if ext[0] >= ext[2] else 2
    mid = (mn2[axis] + mx2[axis]) / 2.0
    hi_y = -np.inf
    lo_y = -np.inf
    for i, m in world2.items():
        n = g.nodes[i]
        if n.mesh is None:
            continue
        for prim in g.meshes[n.mesh].primitives:
            a = g.accessors[prim.attributes.POSITION]
            for cx in (a.min[0], a.max[0]):
                for cy in (a.min[1], a.max[1]):
                    for cz in (a.min[2], a.max[2]):
                        v = m @ np.array([cx, cy, cz, 1.0])
                        if v[axis] >= mid:
                            hi_y = max(hi_y, v[1])
                        else:
                            lo_y = max(lo_y, v[1])
    forward = "?"
    if hi_y > lo_y:
        f = [0.0, 0.0, 0.0]
        f[axis] = 1.0
        forward = f"({f[0]:.2f},{f[2]:.2f})"
    # material defaults
    for mat in g.materials:
        pbr = mat.pbrMetallicRoughness
        if pbr is None:
            continue
        name = (mat.name or "").lower()
        if pbr.metallicFactor is None:
            pbr.metallicFactor = 0.0
        if pbr.roughnessFactor is None:
            pbr.roughnessFactor = 0.8
        key = next((k for k in ROUGH if k in name), None)
        if key:
            pbr.roughnessFactor = ROUGH[key]

    g.save(dst)
    print(f"DIMS ext=({ext[0]:.2f},{ext[1]:.2f},{ext[2]:.2f}) minY={mn2[1]:.3f} "
          f"forward={forward} (axis={'X' if axis == 0 else 'Z'})")
    print(f"saved {dst}")


if __name__ == "__main__":
    main()
