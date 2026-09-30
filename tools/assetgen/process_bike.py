#!/usr/bin/env python3
"""Motorcycle processing pipeline for Sketchfab GLBs.

gltf-transform (dedupe, texture resize) -> normalize_bike.py (ground, center,
wheel rename, PBR) -> print final dims for BikeDef.

Usage: process_bike.py <in.glb> <out.glb> <tex_max> [target_length]
"""
import subprocess
import sys
import tempfile

GT = "/tmp/opencode/node_modules/.bin/gltf-transform"
HERE = __file__.rsplit("/", 1)[0]


def main():
    src, dst, tex = sys.argv[1], sys.argv[2], int(sys.argv[3])
    target = sys.argv[4] if len(sys.argv) > 4 else None
    with tempfile.NamedTemporaryFile(suffix=".glb") as t:
        subprocess.run([GT, "dedup", src, t.name], check=True, capture_output=True)
        subprocess.run([GT, "resize", t.name, t.name,
                        f"--width={tex}", f"--height={tex}"], check=True, capture_output=True)
        cmd = [sys.executable, f"{HERE}/normalize_bike.py", t.name, dst]
        if target:
            cmd.append(target)
        r = subprocess.run(cmd, capture_output=True, text=True)
        print(r.stdout.strip())
        if r.returncode != 0:
            print(r.stderr.strip())
            sys.exit(1)


if __name__ == "__main__":
    main()
