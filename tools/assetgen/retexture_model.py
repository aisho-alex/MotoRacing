#!/usr/bin/env python3
"""Apply generated cel textures to a GLB's materials.

For every `MaterialName=set` mapping the material's base-colour texture is
repointed at `assets/environments/city/buildings/tex/<set>.png` (a copy is placed
next to the GLB). Materials that had no texture get a new texture appended; the
mesh must expose TEXCOORD_0. Unmapped materials are left untouched.

Usage: retexture_model.py <model.glb> <tex_dir> <Material=set> [<Material=set> ...]
"""
import os
import shutil
import sys

from pygltflib import GLTF2, Image, Texture, TextureInfo

MIME = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}


def find_material(g, name):
    for i, m in enumerate(g.materials or []):
        if m.name == name:
            return i
    return -1


def main():
    glb, tex_dir = sys.argv[1], sys.argv[2]
    mapping = dict(a.split("=", 1) for a in sys.argv[3:])
    g = GLTF2().load(glb)
    base = os.path.splitext(os.path.basename(glb))[0]
    glb_dir = os.path.dirname(glb) or "."
    for mat_name, set_name in mapping.items():
        mi = find_material(g, mat_name)
        if mi < 0:
            print(f"  ! material {mat_name!r} not found")
            continue
        src = os.path.join(tex_dir, set_name + ".png")
        if not os.path.exists(src):
            print(f"  ! texture set {set_name!r} missing: {src}")
            continue
        dst_name = f"{base}_{set_name}.png"
        shutil.copyfile(src, os.path.join(glb_dir, dst_name))
        mat = g.materials[mi]
        pbr = mat.pbrMetallicRoughness
        if pbr is None:
            from pygltflib import PbrMetallicRoughness
            pbr = PbrMetallicRoughness()
            mat.pbrMetallicRoughness = pbr
        bct = pbr.baseColorTexture
        if bct is not None and bct.index is not None:
            img_idx = g.textures[bct.index].source
            g.images[img_idx].uri = dst_name
            g.images[img_idx].mimeType = MIME["png"]
            g.images[img_idx].bufferView = None
        else:
            g.images.append(Image(uri=dst_name, mimeType=MIME["png"]))
            g.textures.append(Texture(source=len(g.images) - 1))
            pbr.baseColorTexture = TextureInfo(index=len(g.textures) - 1)
        pbr.baseColorFactor = [1.0, 1.0, 1.0, 1.0]
        print(f"  {mat_name} -> {dst_name}")
    g.save(glb)
    print(f"saved {glb}")


if __name__ == "__main__":
    main()
