# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==11.3.0"]
# ///
"""アプリアイコン (Resources/AppIcon.png, 1024x1024) を生成する。

曇ったガラスを指で拭った跡と、そこから垂れる水滴。
    uv run scripts/make-icon.py
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.png"

# 窓の向こうの夕景
scene = Image.new("RGB", (S, S))
draw = ImageDraw.Draw(scene)
top, bottom = (58, 52, 140), (240, 150, 90)
for y in range(S):
    t = y / S
    draw.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
# 街の灯り。拭った跡からだけくっきり見える
for x, y, r in [(430, 270, 28), (590, 300, 36), (670, 430, 24), (520, 590, 30), (380, 560, 22), (250, 420, 30), (780, 700, 26)]:
    draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 214, 140))

# 曇り: ぼかして白く霞ませ、細かい粒を散らす
fog = scene.filter(ImageFilter.GaussianBlur(60))
fog = Image.blend(fog, Image.new("RGB", (S, S), (235, 235, 240)), 0.5)
grain = ImageDraw.Draw(fog, "RGBA")
rng = random.Random(1)
for _ in range(40000):
    x, y, r = rng.uniform(0, S), rng.uniform(0, S), rng.uniform(0.6, 1.6)
    grain.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rng.randint(25, 70)))

# 拭った跡 (白い部分が拭われた所)
mask = Image.new("L", (S, S), 0)
m = ImageDraw.Draw(mask)
stroke = [(300, 330), (420, 260), (600, 280), (700, 400), (650, 540), (480, 600), (360, 560)]
m.line(stroke, fill=255, width=110, joint="curve")
for x, y in stroke[::len(stroke) - 1]:
    m.ellipse([x - 55, y - 55, x + 55, y + 55], fill=255)
drip_x, drip_top, drip_bottom = 655, 520, 860
m.line([(drip_x, drip_top), (drip_x, drip_bottom)], fill=255, width=26)
m.ellipse([drip_x - 26, drip_bottom - 22, drip_x + 26, drip_bottom + 34], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(10))

icon = Image.composite(scene, fog, mask)

# 水滴の先端の水玉: 縁の影とハイライト
bead = ImageDraw.Draw(icon, "RGBA")
cx, cy = drip_x, drip_bottom + 6
bead.ellipse([cx - 28, cy - 28, cx + 28, cy + 32], outline=(0, 0, 0, 55), width=4)
bead.ellipse([cx - 16, cy - 18, cx - 2, cy - 8], fill=(255, 255, 255, 230))

OUT.parent.mkdir(exist_ok=True)
icon.save(OUT)
print(f"保存: {OUT}")
