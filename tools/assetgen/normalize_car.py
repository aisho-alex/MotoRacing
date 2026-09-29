#!/usr/bin/env python3
"""Normalize open-asset car GLBs for SimpleRacing.

- ground the model (min world y == 0)
- pivot at the wheelbase center (x/z)
- PBR material fixes: metallic=0, per-name roughness, emissive lights
- verify wheel node naming for car.gd ("wheel", front -> contains "front")

Usage: normalize_car.py <in.glb> <out.glb> [--name-prefix X]
"""
import json
import struct
import sys

import numpy as np
from pygltflib import GLTF2

ROUGHNESS = {
    "tire": 0.95,
    "body": 0.32,
    "glass": 0.08,
    "lights": 0.25,
    "interior": 0.85,
    "trim": 0.7,
    "plate": 0.4,
    "badge": 0.35,
}
METALLIC = {
    "tire": 0.0,
    "body": 0.0,
    "glass": 0.0,
    "lights": 0.0,
    "interior": 0.0,
    "trim": 0.15,
    "plate": 0.0,
    "badge": 0.8,
}


def break_wheel_match(name):
    """Rename so car.gd's \"wheel\"-in-name test no longer matches."""
    return name.replace("Wheel", "Wxeel").replace("wheel", "wxeel")


def load(path):
    g = GLTF2().load(path)
    return g


def node_world(g, idx, parent=np.identity(4), out=None):
    if out is None:
        out = {}
    n = g.nodes[idx]
    if n.matrix:
        # glTF matrices are column-major
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


def accessor_bounds(g, acc_idx):
    a = g.accessors[acc_idx]
    return np.array(a.min), np.array(a.max)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    g = load(src)
    scene = g.scenes[g.scene]
    roots = scene.nodes
    assert len(roots) == 1, f"expect single root, got {roots}"
    world = node_world(g, roots[0])

    # Node pass: keep exactly the 4 corner wheel nodes matchable by car.gd
    # ("wheel" in name, front -> fl/fr suffix); everything else wheel-ish
    # (steering wheel, hubcaps, baked mesh children) gets renamed.
    import re
    corner_re = re.compile(r"_(fl|fr|rl|rr|bl|br)\d*$")
    corners = []
    for i in world:
        n = g.nodes[i]
        nm = n.name or ""
        low = nm.lower()
        if "wheel" not in low:
            continue
        m = corner_re.search(low)
        if m and "wheel" in low[:m.start()]:
            corners.append(i)
        else:
            n.name = break_wheel_match(nm)
    if len(corners) == 0:
        print("WARN: no corner wheel nodes; static wheels, ground-only pivot")
    print(f"corner wheels kept: {len(corners)}")

    # axle centers (axis-agnostic): front = fl+fr, rear = rl+rr
    fronts = [i for i in corners if corner_re.search(g.nodes[i].name.lower()).group(1) in ("fl", "fr")]
    rears = [i for i in corners if i not in fronts]
    if corners:
        F = np.mean([world[i][:3, 3] for i in fronts], axis=0)
        R = np.mean([world[i][:3, 3] for i in rears], axis=0)
        print(f"front axle ({F[0]:.2f},{F[1]:.2f},{F[2]:.2f}) rear axle ({R[0]:.2f},{R[1]:.2f},{R[2]:.2f})")
        fwd = F - R
        print(f"forward vector ({fwd[0]:.2f},{fwd[2]:.2f}) in xz")

    # world bounds of all meshes (per-node transform applied)
    mn = np.array([np.inf] * 3)
    mx = -mn
    for i, m in world.items():
        n = g.nodes[i]
        if n.mesh is None:
            continue
        for prim in g.meshes[n.mesh].primitives:
            pmin, pmax = accessor_bounds(g, prim.attributes.POSITION)
            for cx in (pmin[0], pmax[0]):
                for cy in (pmin[1], pmax[1]):
                    for cz in (pmin[2], pmax[2]):
                        v = m @ np.array([cx, cy, cz, 1.0])
                        mn = np.minimum(mn, v[:3])
                        mx = np.maximum(mx, v[:3])
    print(f"world bounds min={mn.round(3)} max={mx.round(3)}")

    # root shift: pivot to wheelbase center, ground to y=0, optional rescale.
    # A new root node is prepended (old root may carry a matrix, which would
    # ignore plain translation/scale properties).
    old_root_idx = roots[0]
    scale = 1.0
    if len(sys.argv) > 3:
        target_len = float(sys.argv[3])
        horiz = max(mx[0] - mn[0], mx[2] - mn[2])
        scale = target_len / horiz
    if corners:
        pivot = ((F + R) / 2.0)
        shift = [-scale * pivot[0], -scale * mn[1], -scale * pivot[2]]
    else:
        shift = [-scale * (mn[0] + mx[0]) / 2.0, -scale * mn[1],
                 -scale * (mn[2] + mx[2]) / 2.0]
    from pygltflib import Node
    new_root = Node()
    new_root.children = [old_root_idx]
    new_root.translation = shift
    new_root.scale = [scale] * 3
    g.nodes.append(new_root)
    g.scenes[g.scene].nodes = [len(g.nodes) - 1]

    # material pass: sane PBR defaults
    for mat in g.materials:
        name = (mat.name or "").lower()
        pbr = mat.pbrMetallicRoughness
        key = next((k for k in ROUGHNESS if k in name), None)
        if pbr:
            if pbr.metallicFactor is None:
                pbr.metallicFactor = 0.0
            if pbr.roughnessFactor is None:
                pbr.roughnessFactor = 0.8
            pbr.metallicFactor = METALLIC.get(key, min(pbr.metallicFactor, 0.2))
            if key:
                pbr.roughnessFactor = ROUGHNESS[key]

    # final measurements (Godot-style, Y-up): dims, axle height, forward
    g2_world = node_world(g, len(g.nodes) - 1)
    fmn = np.array([np.inf] * 3)
    fmx = -fmn
    for i, m in g2_world.items():
        n = g.nodes[i]
        if n.mesh is None:
            continue
        for prim in g.meshes[n.mesh].primitives:
            pmin, pmax = accessor_bounds(g, prim.attributes.POSITION)
            for cx in (pmin[0], pmax[0]):
                for cy in (pmin[1], pmax[1]):
                    for cz in (pmin[2], pmax[2]):
                        v = m @ np.array([cx, cy, cz, 1.0])
                        fmn = np.minimum(fmn, v[:3])
                        fmx = np.maximum(fmx, v[:3])
    axy = [float(g2_world[i][1, 3]) for i in corners] or [0.0]
    fvec = ""
    if corners:
        FF = np.mean([g2_world[i][:3, 3] for i in fronts], axis=0)
        RR = np.mean([g2_world[i][:3, 3] for i in rears], axis=0)
        fv = FF - RR
        fvec = f" forward=({fv[0]:.2f},{fv[2]:.2f})"
    ext = fmx - fmn
    print(f"DIMS ext=({ext[0]:.2f},{ext[1]:.2f},{ext[2]:.2f}) minY={fmn[1]:.3f} "
          f"axle_y={np.mean(axy):.3f}{fvec}")
    g.save(dst)
    print(f"saved {dst}")


if __name__ == "__main__":
    main()
