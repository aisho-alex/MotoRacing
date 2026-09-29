#!/usr/bin/env python3
"""Slice a one-sided curb profile out of a Kenney road tile GLB.

The Kenney "City Kit (Roads)" tile `road-straight-barrier.glb` contains two
raised curbs (left/right edge of a 1x1 m tile). Racer wants a single curb
segment that follows the track edge, so we keep only one side, drop it to the
ground plane (y=0) with the inner base at x=0 and rescale to real meters.

Usage:
    normalize_curb.py <in.glb> <out.glb> [side=right] [width=0.18] [height=0.18]
"""
import sys

import numpy as np
from pygltflib import GLTF2

COMP = {5120: "i1", 5121: "u1", 5122: "i2", 5123: "u2", 5125: "u4", 5126: "f4"}
SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(g, idx):
    a = g.accessors[idx]
    bv = g.bufferViews[a.bufferView]
    blob = g.binary_blob()
    dt, sz = COMP[a.componentType], SIZE[a.componentType]
    n = NCOMP[a.type]
    stride = bv.byteStride or sz * n
    base = (bv.byteOffset or 0) + (a.byteOffset or 0)
    if stride == sz * n:
        return np.frombuffer(blob, dtype=dt, count=a.count * n,
                             offset=base).reshape(a.count, n).copy()
    return np.array([np.frombuffer(blob, dtype=dt, count=n, offset=base + k * stride)
                     for k in range(a.count)])


def write_raw(g, blob, accessor, arr):
    bv = g.bufferViews[accessor.bufferView]
    base = (bv.byteOffset or 0) + (accessor.byteOffset or 0)
    raw = arr.tobytes()
    blob[base:base + len(raw)] = raw


def main():
    src, dst = sys.argv[1], sys.argv[2]
    side = sys.argv[3] if len(sys.argv) > 3 else "right"
    width = float(sys.argv[4]) if len(sys.argv) > 4 else 0.18
    height = float(sys.argv[5]) if len(sys.argv) > 5 else 0.18

    g = GLTF2().load(src)
    prim = g.meshes[0].primitives[0]
    pos = read_accessor(g, prim.attributes.POSITION).astype(np.float64)
    idx = read_accessor(g, prim.indices).reshape(-1).astype(np.int64)
    tris = idx.reshape(-1, 3)

    keep = {
        "right": pos[:, 0] >= 0.44,
        "left": pos[:, 0] <= -0.44,
    }[side]
    tri_keep = keep[tris].all(axis=1)
    kept = tris[tri_keep]
    print(f"{side} curb: {int(tri_keep.sum())}/{len(tris)} tris kept")

    # compact: keep only vertices used by the surviving triangles, in order
    used = np.unique(kept)
    remap = {int(v): k for k, v in enumerate(used)}
    newidx = np.array([[remap[int(v)] for v in t] for t in kept]).reshape(-1)

    # inner base (|x|==0.45, y==0) -> origin; rescale to real meters
    sx = width / 0.05
    sy = height / 0.08
    newpos = pos[used].copy()
    if side == "right":
        newpos[:, 0] = (newpos[:, 0] - 0.45) * sx
    else:
        newpos[:, 0] = (-newpos[:, 0] - 0.45) * sx
    newpos[:, 1] = newpos[:, 1] * sy

    # recompute normals from the kept triangles (non-uniform scale warps them)
    normals = np.zeros_like(newpos)
    tri = newpos[newidx].reshape(-1, 3, 3)
    fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for k, t in enumerate(newidx.reshape(-1, 3)):
        for v in t:
            normals[v] += fn[k]
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)

    blob = bytearray(g.binary_blob())
    write_raw(g, blob, g.accessors[prim.attributes.POSITION], newpos.astype("f4"))
    if prim.attributes.NORMAL is not None:
        write_raw(g, blob, g.accessors[prim.attributes.NORMAL], normals.astype("f4"))
    for attr, ac in (("TEXCOORD_0", prim.attributes.TEXCOORD_0),
                     ("TANGENT", prim.attributes.TANGENT)):
        if ac is not None:
            write_raw(g, blob, g.accessors[ac], read_accessor(g, ac)[used].astype("f4"))
            g.accessors[ac].count = len(used)
    dt = COMP[g.accessors[prim.indices].componentType]
    write_raw(g, blob, g.accessors[prim.indices], newidx.astype(dt))
    pa = g.accessors[prim.attributes.POSITION]
    pa.count = len(used)
    pa.min = [float(x) for x in newpos.min(0)]
    pa.max = [float(x) for x in newpos.max(0)]
    if prim.attributes.NORMAL is not None:
        g.accessors[prim.attributes.NORMAL].count = len(used)
    ia = g.accessors[prim.indices]
    ia.count = len(newidx)
    ia.min = [int(newidx.min())]
    ia.max = [int(newidx.max())]
    g.set_binary_blob(bytes(blob))

    mn, mx = newpos.min(0), newpos.max(0)
    print(f"DIMS x={mx[0]-mn[0]:.2f} y={mx[1]-mn[1]:.2f} z={mx[2]-mn[2]:.2f} "
          f"minY={mn[1]:.3f}")
    g.save(dst)
    print(f"saved {dst}")


if __name__ == "__main__":
    main()
