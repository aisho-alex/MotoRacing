#!/usr/bin/env python3
"""Create or tighten Godot texture imports for environment assets.

Uses VRAM compression and mipmaps for 3D textures. Normal maps get Godot's
normal-map import flag. Missing .import files are initialized without a UID so
the editor can assign one on its next scan.

Usage: python3 patch_imports.py
"""

import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_DIR = ROOT / "assets" / "environments"
TEXTURES = (".png", ".webp")


def res_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def imported_dest(path: Path) -> str:
    rp = res_path(path)
    digest = hashlib.md5(rp.encode()).hexdigest()
    return f"res://.godot/imported/{path.name}-{digest}.ctex"


def import_body(path: Path, normal_map: bool) -> str:
    dest = imported_dest(path)
    normal_flag = 1 if normal_map else 0
    return f"""[remap]

importer="texture"
type="CompressedTexture2D"
path="{dest}"
metadata={{
"vram_texture": true
}}

[deps]

source_file="{res_path(path)}"
dest_files=["{dest}"]

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal_flag}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def patch_import(path: Path) -> bool:
    normal_map = "_normal.png" in path.name
    target = Path(str(path) + ".import")
    body = import_body(path, normal_map)
    if not target.exists():
        target.write_text(body)
        return True

    lines = target.read_text().splitlines()
    out: list[str] = []
    seen = set()
    has_metadata = any(line.strip() == "metadata={" for line in lines)
    metadata_vram = False
    for line in lines:
        if line.strip() == '"vram_texture": false':
            line = line.replace("false", "true")
            metadata_vram = True
        if line.startswith("compress/mode="):
            line = "compress/mode=2"
        elif line.startswith("compress/normal_map="):
            line = f"compress/normal_map={1 if normal_map else 0}"
        elif line.startswith("mipmaps/generate="):
            line = "mipmaps/generate=true"
        out.append(line)
        if line.startswith(("compress/mode=", "compress/normal_map=", "mipmaps/generate=")):
            seen.add(line.split("=", 1)[0])

    if not metadata_vram and not has_metadata:
        for i, line in enumerate(out):
            if line.startswith("path=\""):
                out[i + 1:i + 1] = ["metadata={", '"vram_texture": true', "}"]
                break
    elif not metadata_vram:
        for i, line in enumerate(out):
            if line.strip() == "metadata={":
                out.insert(i + 1, '"vram_texture": true')
                break
    for key, value in (("compress/mode", "2"),
                       ("compress/normal_map", str(int(normal_map))),
                       ("mipmaps/generate", "true")):
        if key not in seen:
            if out and out[-1].strip() != "":
                out.append("")
            out.append(f"{key}={value}")
    target.write_text("\n".join(out) + "\n")
    return False


def main() -> None:
    created = 0
    patched = 0
    for path in sorted(ENV_DIR.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in TEXTURES:
            continue
        if patch_import(path):
            created += 1
        else:
            patched += 1
    print(f"texture imports: {created} created, {patched} patched")


if __name__ == "__main__":
    main()
