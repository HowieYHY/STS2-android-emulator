"""Read-only: extract selected files from a Godot pck (v3, unencrypted) into an output dir.

Usage: python -I pck_extract.py <pck> <out-dir> <regex> [--max-bytes N] [--head N]
--head N writes only the first N bytes of each match (for header inspection).
"""
import struct, sys, os, re, argparse

def entries(f):
    f.seek(0); assert f.read(4) == b"GDPC"
    fmt, *_ = struct.unpack("<4I", f.read(16))
    flags, file_base = struct.unpack("<IQ", f.read(12))
    (dir_offset,) = struct.unpack("<Q", f.read(8))
    base = file_base  # PACK_REL_FILEBASE: relative to pack start (pck starts at 0 here)
    f.seek(dir_offset)
    (count,) = struct.unpack("<I", f.read(4))
    for _ in range(count):
        (plen,) = struct.unpack("<I", f.read(4))
        path = f.read(plen).rstrip(b"\0").decode("utf-8", "replace")
        off, size = struct.unpack("<QQ", f.read(16)); f.read(16)
        (fl,) = struct.unpack("<I", f.read(4))
        yield path, base + off, size, fl

ap = argparse.ArgumentParser()
ap.add_argument("pck"); ap.add_argument("out"); ap.add_argument("pattern")
ap.add_argument("--max-bytes", type=int, default=50_000_000)
ap.add_argument("--head", type=int, default=0)
ap.add_argument("--limit", type=int, default=100000)
a = ap.parse_args()
rx = re.compile(a.pattern)
n = 0
with open(a.pck, "rb") as f:
    for path, off, size, fl in list(entries(f)):
        if not rx.search(path) or size > a.max_bytes:
            continue
        f.seek(off)
        data = f.read(a.head if a.head else size)
        dst = os.path.join(a.out, path.replace("res://", "").lstrip("/"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, "wb").write(data)
        n += 1
        if n >= a.limit: break
print(f"extracted {n} files")
