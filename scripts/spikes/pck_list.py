"""Read-only lister for Godot pack (.pck) format v2/v3.

Usage: python -I pck_list.py <path-to.pck> <output-dir>
Writes <output-dir>/pck_files.txt and prints a header/encryption summary.
Never writes next to the game.
"""
import struct, sys, os, collections

PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2
PACK_SPARSE_BUNDLE = 4
PACK_FILE_ENCRYPTED = 1
PACK_FILE_REMOVAL = 2

def main(pck, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    with open(pck, "rb") as f:
        magic = f.read(4)
        if magic != b"GDPC":
            sys.exit(f"not a pck (magic={magic!r})")
        fmt, vmaj, vmin, vpat = struct.unpack("<4I", f.read(16))
        flags = 0
        dir_offset = None
        if fmt >= 2:
            flags, file_base = struct.unpack("<IQ", f.read(12))
        if fmt >= 3:
            (dir_offset,) = struct.unpack("<Q", f.read(8))
        print(f"format v{fmt}, engine {vmaj}.{vmin}.{vpat}, flags=0x{flags:x}, file_base={file_base}, dir_offset={dir_offset}")
        print(f"  directory encrypted: {bool(flags & PACK_DIR_ENCRYPTED)}")
        print(f"  relative file base:  {bool(flags & PACK_REL_FILEBASE)}")
        print(f"  sparse bundle:       {bool(flags & PACK_SPARSE_BUNDLE)}")
        if flags & PACK_DIR_ENCRYPTED:
            print("Directory is encrypted; cannot list without the key.")
            return
        if dir_offset is not None:
            f.seek(dir_offset)
        else:
            f.seek(4 + 16 + 12 + 64)
        (count,) = struct.unpack("<I", f.read(4))
        enc = 0
        exts = collections.Counter()
        sizes = collections.Counter()
        top = collections.Counter()
        with open(os.path.join(out_dir, "pck_files.txt"), "w", encoding="utf-8") as o:
            for _ in range(count):
                (plen,) = struct.unpack("<I", f.read(4))
                path = f.read(plen).rstrip(b"\0").decode("utf-8", "replace")
                off, size = struct.unpack("<QQ", f.read(16))
                f.read(16)  # md5
                (fflags,) = struct.unpack("<I", f.read(4)) if fmt >= 2 else (0,)
                if fflags & PACK_FILE_ENCRYPTED:
                    enc += 1
                ext = os.path.splitext(path)[1].lower()
                exts[ext] += 1
                sizes[ext] += size
                parts = path.replace("res://", "").split("/")
                top[parts[0] if len(parts) > 1 else "(root)"] += 1
                o.write(f"{size}\t{fflags}\t{path}\n")
        print(f"files: {count}, encrypted files: {enc}")
        print("top folders:", top.most_common(25))
        print("extensions by count:")
        for e, n in exts.most_common(40):
            print(f"  {e or '(none)':14} {n:7}  {sizes[e]/1e6:9.1f} MB")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
