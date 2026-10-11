"""Read-only: dump a Godot 4 project.binary (ECFG) as key = value lines.

Usage: python -I project_binary.py <project.binary>
Decodes simple Variant types; others are shown as <type N, M bytes>.
"""
import struct, sys

def s(b, o):
    (n,) = struct.unpack_from("<I", b, o); o += 4
    v = b[o:o+n].decode("utf-8", "replace"); o += n
    return v, o + ((4 - n % 4) % 4)

def var(b, o):
    (h,) = struct.unpack_from("<I", b, o); o += 4
    t, f64 = h & 0xFF, bool(h & (1 << 16))
    if t == 0: return None, o
    if t == 1: return bool(struct.unpack_from("<I", b, o)[0]), o + 4
    if t == 2:
        return (struct.unpack_from("<q", b, o)[0], o + 8) if f64 else (struct.unpack_from("<i", b, o)[0], o + 4)
    if t == 3:
        return (struct.unpack_from("<d", b, o)[0], o + 8) if f64 else (struct.unpack_from("<f", b, o)[0], o + 4)
    if t in (4, 21, 22 if False else -1): return s(b, o)
    if t == 5: return struct.unpack_from("<2f", b, o), o + 8
    if t == 6: return struct.unpack_from("<2i", b, o), o + 8
    if t == 20: return struct.unpack_from("<4f", b, o), o + 16
    if t == 27:
        (n,) = struct.unpack_from("<I", b, o); o += 4; d = {}
        for _ in range(n & 0x7FFFFFFF):
            k, o = var(b, o); v, o = var(b, o); d[str(k)] = v
        return d, o
    if t == 28:
        (n,) = struct.unpack_from("<I", b, o); o += 4; a = []
        for _ in range(n & 0x7FFFFFFF):
            v, o = var(b, o); a.append(v)
        return a, o
    if t == 34:
        (n,) = struct.unpack_from("<I", b, o); o += 4; a = []
        for _ in range(n):
            v, o = s(b, o); a.append(v)
        return a, o
    raise ValueError(t)

b = open(sys.argv[1], "rb").read()
assert b[:4] == b"ECFG"
(count,) = struct.unpack_from("<I", b, 4); o = 8
for _ in range(count):
    (kl,) = struct.unpack_from("<I", b, o); o += 4
    k = b[o:o+kl].decode(); o += kl
    (vl,) = struct.unpack_from("<I", b, o); o += 4
    try: v, _ = var(b, o)
    except Exception as e: v = f"<type {struct.unpack_from('<I', b, o)[0] & 0xFF}, {vl} bytes>"
    o += vl
    r = repr(v)
    print(f"{k} = {r if len(r) < 400 else r[:400] + '...'}")
