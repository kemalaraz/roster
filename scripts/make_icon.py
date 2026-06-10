#!/usr/bin/env python3
"""Generate the Claude Profiles app icon.

Design:
  Dark purple squircle background with a subtle radial glow.
  Three large profile chips — each a coloured disc with a white person
  silhouette — overlapping like a hand of cards fanned out.
  Draw order: purple (back-left) → coral (back-right) → teal (front-centre).
"""
import shutil, subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

# ── Constants ─────────────────────────────────────────────────────────────────

SIZE    = 1024
CORNER  = int(SIZE * 0.225)

BG_TOP    = (18, 12, 50)
BG_BOTTOM = (48, 22, 95)

# (colour, centre-offset-from-canvas-centre, rotation-degrees)
CHIPS = [
    ((120,  80, 200), (-145, 25), -28),   # purple  — back left
    ((235,  90,  65), ( 145, 25),  28),   # coral   — back right
    (( 30, 175, 185), (   0, -15),  0),   # teal    — front centre
]
CHIP_R = 225   # radius at SIZE=1024

OUT_DIR  = Path(__file__).parent.parent / "resources"
ICONSET  = OUT_DIR / "AppIcon.iconset"
ICNS     = OUT_DIR / "icon.icns"

# ── Drawing helpers ───────────────────────────────────────────────────────────

def gradient_bg(s: int) -> Image.Image:
    img  = Image.new("RGB", (s, s))
    draw = ImageDraw.Draw(img)
    for y in range(s):
        t = y / (s - 1)
        c = tuple(int(BG_TOP[i] + t * (BG_BOTTOM[i] - BG_TOP[i])) for i in range(3))
        draw.line([(0, y), (s, y)], fill=c)
    return img

def squircle_mask(s: int, r: int) -> Image.Image:
    scale = 4
    big = Image.new("L", (s * scale, s * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, s * scale - 1, s * scale - 1], radius=r * scale, fill=255
    )
    return big.resize((s, s), Image.LANCZOS)

def radial_glow(s: int) -> Image.Image:
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    cx = cy = s // 2
    for r in range(int(s * 0.5), int(s * 0.06), -3):
        a = int(14 * (1 - r / (s * 0.5)))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(160, 100, 255, a))
    return glow.filter(ImageFilter.GaussianBlur(s * 0.05))

def person_silhouette(draw: ImageDraw.Draw, cx: float, cy: float,
                      chip_r: float, fill) -> None:
    """Head + rounded-shoulder body centred at (cx, cy)."""
    hr = chip_r * 0.30          # head radius
    bw = chip_r * 0.52          # body half-width
    bh = chip_r * 0.46          # body half-height
    gap = chip_r * 0.06         # gap between head bottom and body top

    head_cy = cy - chip_r * 0.13
    body_cy = head_cy + hr + gap + bh * 0.55

    # head
    draw.ellipse([cx - hr, head_cy - hr, cx + hr, head_cy + hr], fill=fill)
    # body (pill shape)
    draw.rounded_rectangle(
        [cx - bw, body_cy - bh, cx + bw, body_cy + bh + chip_r * 0.30],
        radius=bw,
        fill=fill,
    )

def chip_image(chip_r: int, color: tuple) -> Image.Image:
    """RGBA chip disc with person silhouette."""
    pad  = int(chip_r * 0.30)
    size = (chip_r + pad) * 2
    img  = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = cy = size // 2

    # subtle outer shadow ring
    draw.ellipse(
        [cx - chip_r - 4, cy - chip_r - 4, cx + chip_r + 4, cy + chip_r + 4],
        fill=(*color, 45),
    )
    # main disc
    draw.ellipse(
        [cx - chip_r, cy - chip_r, cx + chip_r, cy + chip_r],
        fill=(*color, 255),
    )
    # bright inner highlight arc (top-left)
    hl_r = int(chip_r * 0.88)
    draw.arc(
        [cx - hl_r, cy - hl_r, cx + hl_r, cy + hl_r],
        start=200, end=320,
        fill=(255, 255, 255, 55),
        width=max(3, chip_r // 18),
    )
    # white rim
    draw.ellipse(
        [cx - chip_r, cy - chip_r, cx + chip_r, cy + chip_r],
        outline=(255, 255, 255, 40),
        width=max(2, chip_r // 30),
    )
    # person
    person_silhouette(draw, cx, cy, chip_r, (255, 255, 255, 235))
    return img

# ── Master render ─────────────────────────────────────────────────────────────

def render(size: int) -> Image.Image:
    scale = size / SIZE
    cx = cy = size // 2

    canvas = gradient_bg(size).convert("RGBA")
    canvas.alpha_composite(radial_glow(size))

    r_px = int(CHIP_R * scale)
    for color, (ox, oy), angle in CHIPS:
        ch = chip_image(r_px, color)
        if angle:
            ch = ch.rotate(-angle, expand=True, resample=Image.BICUBIC)
        cw, ch_h = ch.size
        dx = int(ox * scale)
        dy = int(oy * scale)
        canvas.alpha_composite(ch, dest=(cx + dx - cw // 2, cy + dy - ch_h // 2))

    mask   = squircle_mask(size, int(CORNER * scale))
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(canvas, mask=mask)
    return result

# ── ICNS export ───────────────────────────────────────────────────────────────

def build_icns():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir()

    master = render(1024)
    print("  Rendered 1024×1024 master")

    for px in [16, 32, 64, 128, 256, 512, 1024]:
        img = master.resize((px, px), Image.LANCZOS)
        img.save(ICONSET / f"icon_{px}x{px}.png", "PNG")
        if px <= 512:
            master.resize((px * 2, px * 2), Image.LANCZOS).save(
                ICONSET / f"icon_{px}x{px}@2x.png", "PNG"
            )
        print(f"  {px}×{px}  ✓")

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    shutil.rmtree(ICONSET)
    print(f"\n  ✓  {ICNS}  ({ICNS.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    print("Generating Claude Profiles icon …\n")
    build_icns()
