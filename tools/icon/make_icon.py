"""Draws the app's launcher icon (original artwork; no game assets).

Usage: python -I tools/icon/make_icon.py
Writes shell/icons/{icon_192,foreground_432,background_432,monochrome_432}.png for the Android adaptive icon:
a dark spire with lit windows and a teal flame on top, against a dusk sky with an orange glow over a dark sea,
in the spirit of the game's main menu. Drawn at 4x and downsampled for smooth edges.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "shell", "icons")
S = 4  # supersampling factor
SKY_TOP = (44, 34, 66)
SKY_LOW = (70, 52, 70)
SEA = (22, 46, 54)
GLOW = (255, 150, 40)
TOWER = (34, 22, 40)
TOWER_EDGE = (52, 34, 58)
WINDOW = (255, 170, 70)
FLAME = (70, 225, 235)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background(size):
    n = size * S
    img = Image.new("RGB", (n, n))
    px = img.load()
    horizon = int(n * 0.74)
    for y in range(n):
        row = lerp(SKY_TOP, SKY_LOW, y / horizon) if y < horizon else lerp(SEA, (12, 26, 32), (y - horizon) / (n - horizon))
        for x in range(n):
            px[x, y] = row
    # Orange fire glow high in the sky.
    glow = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(glow)
    cx, cy, r = n * 0.5, n * 0.26, n * 0.36
    for i in range(40, 0, -1):
        f = i / 40
        d.ellipse([cx - r * f * 1.25, cy - r * f * 0.8, cx + r * f * 1.25, cy + r * f * 0.8], fill=int(230 * (1 - f) ** 1.6))
    glow = glow.filter(ImageFilter.GaussianBlur(n * 0.03))
    img = Image.composite(Image.new("RGB", (n, n), GLOW), img, glow)
    # Faint glow reflected on the sea.
    refl = Image.new("L", (n, n), 0)
    ImageDraw.Draw(refl).ellipse([n * 0.38, horizon + n * 0.02, n * 0.62, horizon + n * 0.12], fill=60)
    refl = refl.filter(ImageFilter.GaussianBlur(n * 0.02))
    img = Image.composite(Image.new("RGB", (n, n), GLOW), img, refl)
    return img.resize((size, size), Image.LANCZOS)


def tower_shape(n, mono=False):
    """RGBA layer with the spire, centred in the adaptive icon's safe zone (middle 2/3)."""
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Kept inside the adaptive icon's safe zone (the middle 2/3: 0.167-0.833 of the canvas).
    base_y, top_y = n * 0.78, n * 0.36
    base_half, top_half = n * 0.085, n * 0.058
    body = TOWER if not mono else (255, 255, 255)
    d.polygon([(n / 2 - base_half, base_y), (n / 2 - top_half, top_y), (n / 2 + top_half, top_y),
               (n / 2 + base_half, base_y)], fill=body + (255,))
    # A flat crown with battlements (the game's spire is a tower, not a cone), and a broader foundation.
    crown = top_half * 1.25
    d.rectangle([n / 2 - crown, top_y - n * 0.035, n / 2 + crown, top_y + n * 0.005], fill=body + (255,))
    merlon = crown * 2 / 5
    for i in (0, 2, 4):
        x0 = n / 2 - crown + merlon * i
        d.rectangle([x0, top_y - n * 0.06, x0 + merlon, top_y - n * 0.03], fill=body + (255,))
    d.rectangle([n / 2 - base_half * 1.5, base_y - n * 0.02, n / 2 + base_half * 1.5, base_y + n * 0.015],
                fill=body + (255,))
    if mono:
        # Monochrome (themed) icons are a single alpha shape; cut the windows and flame out of / onto it.
        for wx, wy in windows(n, top_y, base_y, base_half, top_half):
            d.ellipse([wx - n * 0.008, wy - n * 0.012, wx + n * 0.008, wy + n * 0.012], fill=(0, 0, 0, 0))
        flame(d, n, top_y - n * 0.065, (255, 255, 255, 255))
        return img
    # Spiral bands winding up the tower, lighter edge on the left.
    for k in range(1, 5):
        t = k / 5
        y0 = base_y - (base_y - top_y) * t
        y1 = y0 - (base_y - top_y) / 5 * 0.6
        half0 = base_half + (top_half - base_half) * t
        d.line([(n / 2 - half0, y0), (n / 2 + half0, y1)], fill=TOWER_EDGE + (255,), width=max(1, int(n * 0.007)))
    d.line([(n / 2 - base_half, base_y), (n / 2 - top_half, top_y)], fill=TOWER_EDGE + (255,), width=int(n * 0.008))
    for wx, wy in windows(n, top_y, base_y, base_half, top_half):
        d.ellipse([wx - n * 0.007, wy - n * 0.011, wx + n * 0.007, wy + n * 0.011], fill=WINDOW + (255,))
    # Teal flame on the tip, with a soft halo.
    halo = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    fy = top_y - n * 0.1
    hd.ellipse([n / 2 - n * 0.07, fy - n * 0.07, n / 2 + n * 0.07, fy + n * 0.05], fill=FLAME + (120,))
    halo = halo.filter(ImageFilter.GaussianBlur(n * 0.025))
    img = Image.alpha_composite(halo, img)
    flame(ImageDraw.Draw(img), n, top_y - n * 0.065, FLAME + (255,))
    return img


def windows(n, top_y, base_y, base_half, top_half):
    """Lit windows scattered up the tower (deterministic)."""
    out = []
    for k in range(7):
        t = (k + 0.6) / 7
        y = base_y - (base_y - top_y) * t * 0.92
        half = base_half + (top_half - base_half) * t
        offset = math.sin(k * 2.39) * half * 0.5
        out.append((n / 2 + offset, y))
    return out


def flame(d, n, tip_base_y, colour):
    """A teardrop flame whose bottom sits on the roof point."""
    w, h = n * 0.026, n * 0.07
    cx, by = n / 2, tip_base_y + n * 0.005
    pts = []
    for i in range(41):
        a = math.pi * i / 40
        x = math.cos(a) * w
        y = -math.sin(a) * w * 0.9
        pts.append((cx + x, by - w + y + w))
    pts = [(cx - w, by - w * 0.6)] + [(cx + math.cos(math.pi * i / 40) * w, by - w * 0.6 + math.sin(math.pi * i / 40) * w * 0.6)
                                     for i in range(41)] + [(cx + w, by - w * 0.6), (cx, by - h)]
    d.polygon(pts, fill=colour)


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 432 * S
    bg = background(432)
    fg = tower_shape(n).resize((432, 432), Image.LANCZOS)
    mono = tower_shape(n, mono=True).resize((432, 432), Image.LANCZOS)
    bg.save(os.path.join(OUT, "background_432.png"))
    fg.save(os.path.join(OUT, "foreground_432.png"))
    mono.save(os.path.join(OUT, "monochrome_432.png"))
    # Legacy (non-adaptive) icon: the composite, cropped like a launcher would (adaptive icons show the middle 2/3).
    full = Image.alpha_composite(bg.convert("RGBA"), fg)
    full.crop((36, 36, 396, 396)).resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "icon_192.png"))
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
