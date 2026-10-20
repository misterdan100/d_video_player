# Genera los PNG del icono (claro, oscuro, tintado) a 1024x1024.
# Uso: python tools/make_icon.py Sources/Assets.xcassets/AppIcon.appiconset  (requiere playwright + Pillow)
import sys
from playwright.sync_api import sync_playwright
from PIL import Image

# Geometría común (lienzo 1024). D con contraforma de "play" + barra de scrub.
D_PATH = "M 328 208 H 512 A 240 240 0 0 1 512 688 H 328 A 56 56 0 0 1 272 632 V 264 A 56 56 0 0 1 328 208 Z"
TRI = "432,348 432,548 604,448"

def svg(variant):
    if variant == "light":
        bg = """
        <rect width="1024" height="1024" fill="url(#bg)"/>
        <rect width="1024" height="1024" fill="url(#glowA)"/>
        <rect width="1024" height="1024" fill="url(#glowB)"/>"""
        d_fill, d_hi = "url(#dFill)", 0.35
        track, prog_a, prog_b, knob = "rgba(255,255,255,0.22)", "#FF5F8F", "#FFB04F", "#FFFFFF"
        shadow = 0.45
    elif variant == "dark":
        bg = ""
        d_fill, d_hi = "url(#dFillDark)", 0.25
        track, prog_a, prog_b, knob = "rgba(255,255,255,0.18)", "#FF5F8F", "#FFB04F", "#FFFFFF"
        shadow = 0.0
    else:  # tinted: escala de grises, el sistema aplica el tinte
        bg = ""
        d_fill, d_hi = "url(#dFillGray)", 0.0
        track, prog_a, prog_b, knob = "rgba(255,255,255,0.30)", "#E6E6E6", "#FFFFFF", "#FFFFFF"
        shadow = 0.0

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3A1F8F"/>
      <stop offset="0.55" stop-color="#1A1550"/>
      <stop offset="1" stop-color="#070B1F"/>
    </linearGradient>
    <radialGradient id="glowA" cx="0.42" cy="0.40" r="0.55">
      <stop offset="0" stop-color="#8B6CFF" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#8B6CFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowB" cx="0.85" cy="0.92" r="0.45">
      <stop offset="0" stop-color="#2EC5FF" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#2EC5FF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="dFill" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#C9D8FF"/>
    </linearGradient>
    <linearGradient id="dFillDark" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#E9E3FF"/>
      <stop offset="1" stop-color="#9C8CFF"/>
    </linearGradient>
    <linearGradient id="dFillGray" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#BDBDBD"/>
    </linearGradient>
    <linearGradient id="prog" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{prog_a}"/>
      <stop offset="1" stop-color="{prog_b}"/>
    </linearGradient>
    <linearGradient id="hi" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="{d_hi}"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <mask id="dMask">
      <path d="{D_PATH}" fill="white"/>
      <polygon points="{TRI}" fill="black" stroke="black" stroke-width="44" stroke-linejoin="round"/>
    </mask>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="22" stdDeviation="28" flood-color="#05061A" flood-opacity="{shadow}"/>
    </filter>
    <filter id="knobGlow" x="-100%" y="-100%" width="300%" height="300%">
      <feDropShadow dx="0" dy="0" stdDeviation="14" flood-color="{prog_b}" flood-opacity="0.9"/>
    </filter>
  </defs>
  {bg}
  <g filter="url(#shadow)">
    <rect width="1024" height="1024" fill="{d_fill}" mask="url(#dMask)"/>
  </g>
  <rect width="1024" height="1024" fill="url(#hi)" mask="url(#dMask)"/>
  <!-- Línea de tiempo (scrub) -->
  <rect x="272" y="781" width="480" height="14" rx="7" fill="{track}"/>
  <rect x="272" y="781" width="330" height="14" rx="7" fill="url(#prog)"/>
  <circle cx="602" cy="788" r="28" fill="{knob}" filter="url(#knobGlow)"/>
</svg>"""

out = sys.argv[1]
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 1024, "height": 1024})
    for v, name in [("light", "AppIcon.png"), ("dark", "AppIcon-dark.png"), ("tinted", "AppIcon-tinted.png")]:
        pg.set_content(f'<html><body style="margin:0;background:transparent">{svg(v)}</body></html>')
        path = f"{out}/{name}"
        pg.screenshot(path=path, omit_background=(v != "light"), clip={"x":0,"y":0,"width":1024,"height":1024})
        if v == "light":
            Image.open(path).convert("RGB").save(path)  # sin canal alfa
        if v == "tinted":
            im = Image.open(path).convert("LA").convert("RGBA")
            im.save(path)
        print(name, Image.open(path).mode, Image.open(path).size)
    b.close()
