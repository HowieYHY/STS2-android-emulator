"""Build textures_astc.pck: ASTC copies of the game's desktop GPU textures, for phones.

Usage: python -I build_textures.py --game-dir "<Steam>/Slay the Spire 2" --out <dir> [--godot <exe>] [--only <regex>]

The PC build ships its VRAM textures only as BC1/BC3/BC7 (`path.s3tc` / `path.bptc` in each .import file).
Phone GPUs can't sample those, so Godot decompresses them on the CPU at load time into RGBA8: 4x the memory, slow
loads and hitches the first time an effect is shown. This writes, for each such texture:
  - .godot/imported/<name>.astc.ctex  the same image in ASTC 4x4 (tools/astc/transcode.gd)
  - <source>.import                   the game's .import with a `path.astc=` line added
Godot's import remap picks the first `path.<feature>` the device supports, so phones with ASTC load the new file
and everything else keeps the original. boot.gd mounts the pack over the game's, so these .import files win.

Converted textures are cached by content hash in <out>/astc_cache, so a rebuild only converts what changed.
Output goes to --out, never into the repo. The game folder is only read.
"""
import argparse
import hashlib
import os
import re
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pcklib  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANSCODER = os.path.join(REPO, "tools", "astc")
DEFAULT_GODOT = r"D:\Tools\Godot\Godot_v4.5.1-stable_mono_win64_console.exe"
BC_FORMATS = {17: "DXT1", 18: "DXT3", 19: "DXT5", 22: "BPTC_RGBA"}  # Image::Format values (Godot 4.5)
DESKTOP_PATH = re.compile(r'^path\.(s3tc|bptc)="(res://\.godot/imported/[^"]+)\.(s3tc|bptc)\.ctex"$', re.M)


def bc_texture(data: bytes) -> bool:
    """True for a GST2 texture stored as a plain image in a BC format without mipmaps (what transcode.gd handles)."""
    if len(data) < 52 or data[:4] != b"GST2":
        return False
    data_format, _w, _h, mipmaps, image_format = struct.unpack_from("<IHHII", data, 36)
    return data_format == 0 and image_format in BC_FORMATS and mipmaps == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    ap.add_argument("--only", help="regex on the source path, for testing a few textures")
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    if os.path.normcase(out_dir + os.sep).startswith(os.path.normcase(REPO + os.sep)):
        sys.exit("--out must be outside the repo (it holds converted game assets).")
    cache_in = os.path.join(out_dir, "astc_cache", "in")
    cache_out = os.path.join(out_dir, "astc_cache", "out")
    os.makedirs(cache_in, exist_ok=True)
    os.makedirs(cache_out, exist_ok=True)

    pck = pcklib.PckReader(os.path.join(args.game_dir, "SlayTheSpire2.pck"))
    print(f"game pck: Godot {pck.major}.{pck.minor}.{pck.patch}, {len(pck.entries)} files")

    # 1. Find .import files whose desktop texture is a BC image; stage the ones not converted yet.
    jobs = []  # (import path, import text, imported base path, content hash)
    skipped = 0
    for path in pck.entries:
        if not path.endswith(".import") or (args.only and not re.search(args.only, path)):
            continue
        text = pck.read(path).decode("utf-8")
        if "path.astc=" in text:
            continue
        m = DESKTOP_PATH.search(text)
        if not m:
            continue
        ctex_path = f"{m.group(2)}.{m.group(3)}.ctex"[len("res://"):]
        if ctex_path not in pck.entries:
            skipped += 1
            continue
        data = pck.read(ctex_path)
        if not bc_texture(data):
            skipped += 1
            continue
        digest = hashlib.sha1(data).hexdigest()
        if not os.path.exists(os.path.join(cache_out, digest + ".ctex")):
            with open(os.path.join(cache_in, digest + ".ctex"), "wb") as f:
                f.write(data)
        jobs.append((path, text, m, digest))
    staged = len(os.listdir(cache_in))
    print(f"{len(jobs)} BC textures ({staged} to convert, {skipped} not convertible, kept as is)")

    # 2. Convert what isn't cached yet.
    if staged:
        r = subprocess.run([args.godot, "--headless", "--path", TRANSCODER, "--script", "transcode.gd", "--",
                            cache_in, cache_out])
        if r.returncode != 0:
            sys.exit("transcode.gd failed (see the FAILED lines above)")
        for name in os.listdir(cache_in):
            os.remove(os.path.join(cache_in, name))

    # 3. The pack: ASTC textures + .import files with path.astc added right after the desktop path line.
    files = {}
    for import_path, text, m, digest in jobs:
        astc_res = f"{m.group(2)}.astc.ctex"
        with open(os.path.join(cache_out, digest + ".ctex"), "rb") as f:
            files[astc_res[len("res://"):]] = f.read()
        line = m.group(0)
        files[import_path] = text.replace(line, f'{line}\npath.astc="{astc_res}"', 1).encode("utf-8")
    pck.close()
    out_pck = os.path.join(out_dir, "textures_astc.pck")
    pcklib.write_pck(out_pck, files)
    print(f"wrote {out_pck}: {len(jobs)} textures, {os.path.getsize(out_pck) / 1048576:.1f} MB")


if __name__ == "__main__":
    main()
