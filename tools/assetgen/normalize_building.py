#!/usr/bin/env python3
"""Normalize a building GLB: ground y=0, pivot at footprint center (x/z),
optional rescale so the max horizontal dimension equals target meters.

Usage: normalize_building.py <in.glb> <out.glb> [target_max_dim]
"""
import sys

import numpy as np
from pygltflib import GLTF2

import importlib.util
spec = importlib.util.spec_from_file_location(
    "nc", __file__.rsplit("/", 1)[0] + "/normalize_car.py")
nc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nc)


def bounds(g, world):
    mn = np.array([np.inf] * 3)
    mx = -mn
    for i, m in world.items():
        n = g.nodes[i]
        if n.mesh is None:
            continue
        for prim in g.meshes[n.mesh].primitives:
            pmin, pmax = nc.accessor_bounds(g, prim.attributes.POSITION)
            for cx in (pmin[0], pmax[0]):
                for cy in (pmin[1], pmax[1]):
                    for cz in (pmin[2], pmax[2]):
                        v = m @ np.array([cx, cy, cz, 1.0])
                        mn = np.minimum(mn, v[:3])
                        mx = np.maximum(mx, v[:3])
    return mn, mx


def main():
    src, dst = sys.argv[1], sys.argv[2]
    g = GLTF2().load(src)
    scene = g.scenes[g.scene]
    roots = scene.nodes
    assert len(roots) == 1, f"expect single root, got {roots}"
    world = nc.node_world(g, roots[0])
    mn, mx = bounds(g, world)
    print(f"raw bounds min={mn.round(2)} max={mx.round(2)}")

    scale = 1.0
    if len(sys.argv) > 3:
        target = float(sys.argv[3])
        horiz = max(mx[0] - mn[0], mx[2] - mn[2])
        height = mx[1] - mn[1]
        # shrunk footprints get clamped; diorama-scale models get grown so
        # the height lands in the 12..30 m band expected by the placement
        if horiz > target:
            scale = target / horiz
            print(f"rescale x{scale:.3f} (footprint {horiz:.1f}m -> {target:.1f}m)")
        elif height < 10.0:
            scale = 14.0 / height
            print(f"grow x{scale:.3f} (height {height:.1f}m -> ~14m)")
    shift = [-scale * (mn[0] + mx[0]) / 2.0, -scale * mn[1],
             -scale * (mn[2] + mx[2]) / 2.0]
    from pygltflib import Node
    new_root = Node()
    new_root.children = [roots[0]]
    new_root.translation = shift
    new_root.scale = [scale] * 3
    g.nodes.append(new_root)
    g.scenes[g.scene].nodes = [len(g.nodes) - 1]

    # final measurements
    w2 = nc.node_world(g, len(g.nodes) - 1)
    fmn, fmx = bounds(g, w2)
    ext = fmx - fmn
    print(f"DIMS footprint=({ext[0]:.1f} x {ext[2]:.1f}) height={ext[1]:.1f} "
          f"minY={fmn[1]:.3f}")
    g.save(dst)
    print(f"saved {dst}")


if __name__ == "__main__":
    main()
