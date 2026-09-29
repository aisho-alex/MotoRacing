#!/usr/bin/env python3
"""Extract embedded GLB textures to sibling files and reference them by URI.

Avoids Godot's double-storage (embedded copies get extracted next to the
.glb on import anyway).

Usage: externalize_textures.py <file.glb>
"""
import os
import sys

from pygltflib import GLTF2, Image


def main():
    path = sys.argv[1]
    g = GLTF2().load(path)
    base = os.path.splitext(path)[0]
    blob = g.binary_blob()
    if blob is None:
        print("no binary blob, nothing to do")
        return
    ext_counts = {}
    for idx, img in enumerate(g.images):
        if img.uri:
            continue
        if img.bufferView is None:
            continue
        bv = g.bufferViews[img.bufferView]
        off = bv.byteOffset or 0
        data = blob[off:off + bv.byteLength]
        mime = (img.mimeType or "image/png").lower()
        ext = ".png" if "png" in mime else (".jpg" if "jpeg" in mime or "jpg" in mime else ".bin")
        ext_counts[ext] = ext_counts.get(ext, 0) + 1
        fname = f"{os.path.basename(base)}_{idx}{ext}"
        with open(os.path.join(os.path.dirname(path) or ".", fname), "wb") as f:
            f.write(data)
        g.images[idx] = Image(uri=fname, mimeType=mime)

    # rebuild bufferViews/buffer without the now-orphaned image views
    keep = {}
    new_views = []
    new_blob = bytearray()
    from pygltflib import BufferView
    for vi, bv in enumerate(g.bufferViews):
        # skip views still referenced by something other than dropped images
        if _view_used(g, vi, skip_images=True):
            off = bv.byteOffset or 0
            pad = (4 - len(new_blob) % 4) % 4
            new_blob.extend(b"\x00" * pad)
            keep[vi] = len(new_views)
            nv = BufferView(buffer=0, byteOffset=len(new_blob), byteLength=bv.byteLength)
            if bv.byteStride:
                nv.byteStride = bv.byteStride
            if bv.target:
                nv.target = bv.target
            new_views.append(nv)
            new_blob.extend(blob[off:off + bv.byteLength])
    g.bufferViews = new_views
    for img in g.images:
        if img.bufferView is not None and img.bufferView in keep:
            img.bufferView = keep[img.bufferView]
        else:
            img.bufferView = None
    # remap remaining references (accessors etc.)
    for acc in g.accessors or []:
        if acc.bufferView is not None:
            acc.bufferView = keep.get(acc.bufferView, acc.bufferView)
    for sk in g.skins or []:
        if sk.inverseBindMatrices is not None:
            sk.inverseBindMatrices = keep.get(sk.inverseBindMatrices, sk.inverseBindMatrices)
    for m in g.meshes or []:
        for prim in m.primitives or []:
            for tgt in (prim.targets or []):
                for attr in tgt.values():
                    if attr.bufferView is not None:
                        attr.bufferView = keep.get(attr.bufferView, attr.bufferView)
    for a in g.animations or []:
        for ch in a.channels or []:
            pass
        for s in a.samplers or []:
            if s.output is not None:
                acc = g.accessors[s.output]
                if acc.bufferView is not None:
                    acc.bufferView = keep.get(acc.bufferView, acc.bufferView)
            if s.input is not None:
                acc = g.accessors[s.input]
                if acc.bufferView is not None:
                    acc.bufferView = keep.get(acc.bufferView, acc.bufferView)
    from pygltflib import Buffer
    buf = Buffer()
    buf.byteLength = len(new_blob)
    g.buffers = [buf]
    g.set_binary_blob(bytes(new_blob))
    g.save(path)
    print(f"externalized {sum(ext_counts.values())} textures: {ext_counts}, buffer -> {len(new_blob)//1024} KB")


def _view_used(g, vi, skip_images):
    for acc in g.accessors or []:
        if acc.bufferView == vi:
            return True
    for m in g.meshes or []:
        for prim in m.primitives or []:
            for tgt in (prim.targets or []):
                for attr in tgt.values():
                    if attr.bufferView == vi:
                        return True
    for sk in g.skins or []:
        if sk.inverseBindMatrices == vi:
            return True
    for a in g.animations or []:
        for s in a.samplers or []:
            if s.input == vi or s.output == vi:
                return True
    if not skip_images:
        for img in g.images or []:
            if img.bufferView == vi:
                return True
    return False


if __name__ == "__main__":
    main()
