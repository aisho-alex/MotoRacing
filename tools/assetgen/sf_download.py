#!/usr/bin/env python3
"""Download a Sketchfab model as GLB (from the downloadable archive).

Usage: sf_download.py <uid> <out.glb>
"""
import json
import sys
import urllib.request
import zipfile
import io

TOKEN = open("/tmp/opencode/sketchfab_token").read().strip()


def main():
    uid, dst = sys.argv[1], sys.argv[2]
    req = urllib.request.Request(
        f"https://api.sketchfab.com/v3/models/{uid}/download",
        headers={"Authorization": f"Token {TOKEN}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        info = json.load(r)
    pick = info.get("glb") or info.get("gltf")
    if pick is None:
        print("no downloadable glb/gltf archive"); sys.exit(1)
    with urllib.request.urlopen(urllib.request.Request(pick["url"]), timeout=300) as r:
        blob = r.read()
    if blob[:4] == b"glTF":
        # glb endpoint serves the raw binary
        with open(dst, "wb") as f:
            f.write(blob)
        print(f"saved {dst} ({len(blob)//1024} KB glb)")
        return
    zf = zipfile.ZipFile(io.BytesIO(blob))
    glbs = [n for n in zf.namelist() if n.lower().endswith(".glb")]
    if glbs:
        with open(dst, "wb") as f:
            f.write(zf.read(glbs[0]))
        print(f"saved {dst} ({len(blob)//1024} KB zip)")
        return
    # gltf archive: gltf + bin + textures; keep archive for gltf-transform
    with open(dst.replace(".glb", "_gltf.zip"), "wb") as f:
        f.write(blob)
    print(f"gltf archive saved (no single glb): {dst.replace('.glb', '_gltf.zip')}")


if __name__ == "__main__":
    main()
