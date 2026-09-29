#!/usr/bin/env python3
"""Full car-processing pipeline for Sketchfab GLBs.

gltf-transform (dedupe, texture resize) -> normalize_car.py (ground, pivot,
corner-wheel naming, PBR fixes) -> measure final dims for CarDef.

Usage: process_car.py <in.glb> <out.glb> <tex_max>   (tex_max: 1024 or 512)
"""
import json
import subprocess
import sys
import tempfile

GT = "/tmp/opencode/node_modules/.bin/gltf-transform"
HERE = __file__.rsplit("/", 1)[0]


def main():
    src, dst, tex = sys.argv[1], sys.argv[2], int(sys.argv[3])
    with tempfile.NamedTemporaryFile(suffix=".glb") as t:
        subprocess.run([GT, "dedup", src, t.name], check=True,
                       capture_output=True)
        subprocess.run([GT, "resize", t.name, t.name,
                        f"--width={tex}", f"--height={tex}"], check=True,
                       capture_output=True)
        cmd = [sys.executable, f"{HERE}/normalize_car.py", t.name, dst]
        if len(sys.argv) > 4:
            cmd.append(sys.argv[4])
        r = subprocess.run(cmd, capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode != 0:
            print(r.stderr.strip()); sys.exit(1)
    # final measurements for CarDef
    import trimesh
    scene = trimesh.load(dst, process=False)
    b = scene.bounds
    ext = b[1] - b[0]
    from pygltflib import GLTF2
    import numpy as np
    g = GLTF2().load(dst)
    import importlib.util
    spec = importlib.util.spec_from_file_location("nc", f"{HERE}/normalize_car.py")
    nc = importlib.util.module_from_spec(spec); spec.loader.exec_module(nc)
    world = nc.node_world(g, g.scenes[g.scene].nodes[0])
    axles = [float(world[i][1, 3]) for i in world
             if "wheel" in (g.nodes[i].name or "").lower()]
    print(f"DIMS len_x={ext[0]:.2f} len_y={ext[1]:.2f} len_z={ext[2]:.2f} "
          f"minY={b[0][1]:.3f} axle_y={round(sum(axles)/len(axles), 3) if axles else 0}")


if __name__ == "__main__":
    main()
