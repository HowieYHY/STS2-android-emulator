"""Minimal reader/writer for Godot 4 pack files (format v3, unencrypted) and project.binary (ECFG).

Only what the port needs: list/read entries of the game's pck, write a small overlay pck, and
rewrite project.binary while keeping every value's raw bytes untouched.
"""
from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass

PACK_FORMAT = 3
PACK_REL_FILEBASE = 2
PACK_DIR_ENCRYPTED = 1
PACK_FILE_ENCRYPTED = 1
ALIGN = 32


@dataclass
class Entry:
    path: str  # without "res://"
    offset: int  # absolute offset in the pck file
    size: int
    flags: int


class PckReader:
    def __init__(self, path: str):
        self.f = open(path, "rb")
        f = self.f
        if f.read(4) != b"GDPC":
            raise ValueError(f"{path}: not a Godot pck")
        fmt, self.major, self.minor, self.patch = struct.unpack("<4I", f.read(16))
        if fmt != PACK_FORMAT:
            raise ValueError(f"{path}: pck format v{fmt}, expected v{PACK_FORMAT}")
        flags, file_base, dir_offset = struct.unpack("<IQQ", f.read(20))
        if flags & PACK_DIR_ENCRYPTED:
            raise ValueError(f"{path}: pck directory is encrypted")
        base = file_base  # PACK_REL_FILEBASE: relative to pck start, which is 0 for a standalone pck
        f.seek(dir_offset)
        (count,) = struct.unpack("<I", f.read(4))
        self.entries: dict[str, Entry] = {}
        for _ in range(count):
            (plen,) = struct.unpack("<I", f.read(4))
            p = f.read(plen).rstrip(b"\0").decode("utf-8")
            off, size = struct.unpack("<QQ", f.read(16))
            f.read(16)  # md5
            (fl,) = struct.unpack("<I", f.read(4))
            p = p.removeprefix("res://")
            self.entries[p] = Entry(p, base + off, size, fl)

    def read(self, path: str) -> bytes:
        e = self.entries[path]
        if e.flags & PACK_FILE_ENCRYPTED:
            raise ValueError(f"{path} is encrypted")
        self.f.seek(e.offset)
        return self.f.read(e.size)

    def close(self):
        self.f.close()


def write_pck(out_path: str, files: dict[str, bytes], version=(4, 5, 1)) -> None:
    """Write a pck v3 containing `files` (keys are paths without "res://")."""
    header_size = 4 + 16 + 20 + 16 * 4
    file_base = (header_size + ALIGN - 1) // ALIGN * ALIGN
    with open(out_path, "wb") as f:
        f.write(b"\0" * file_base)
        records = []
        for path in sorted(files):
            data = files[path]
            rel = f.tell() - file_base
            f.write(data)
            pad = (-f.tell()) % ALIGN
            f.write(b"\0" * pad)
            records.append((path, rel, len(data), hashlib.md5(data).digest()))
        dir_offset = f.tell()
        f.write(struct.pack("<I", len(records)))
        for path, rel, size, md5 in records:
            pb = path.encode("utf-8")
            pb += b"\0" * ((-len(pb)) % 4)  # same padding as Godot's PCKPacker (_get_pad(4, len))
            f.write(struct.pack("<I", len(pb)) + pb)
            f.write(struct.pack("<QQ", rel, size) + md5 + struct.pack("<I", 0))
        f.seek(0)
        f.write(b"GDPC" + struct.pack("<4I", PACK_FORMAT, *version))
        f.write(struct.pack("<IQQ", PACK_REL_FILEBASE, file_base, dir_offset))


# ---- project.binary (ECFG) ----

def read_ecfg(data: bytes) -> list[tuple[str, bytes]]:
    """Return [(key, raw_variant_bytes)] in file order (order matters: it sets autoload order)."""
    if data[:4] != b"ECFG":
        raise ValueError("not a project.binary")
    (count,) = struct.unpack_from("<I", data, 4)
    o, out = 8, []
    for _ in range(count):
        (kl,) = struct.unpack_from("<I", data, o); o += 4
        k = data[o:o + kl].decode("utf-8"); o += kl
        (vl,) = struct.unpack_from("<I", data, o); o += 4
        out.append((k, data[o:o + vl])); o += vl
    return out


def write_ecfg(items: list[tuple[str, bytes]]) -> bytes:
    out = bytearray(b"ECFG" + struct.pack("<I", len(items)))
    for k, v in items:
        kb = k.encode("utf-8")
        out += struct.pack("<I", len(kb)) + kb + struct.pack("<I", len(v)) + v
    return bytes(out)


def variant_string(s: str) -> bytes:
    """Encode a Godot Variant STRING (type 4)."""
    b = s.encode("utf-8")
    return struct.pack("<II", 4, len(b)) + b + b"\0" * ((-len(b)) % 4)
