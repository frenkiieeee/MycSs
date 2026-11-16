#!/usr/bin/env python3
"""Generates the macOS app icon and the menu bar icon from the mascot paths.

    python3 generate.py        (needs rsvg-convert)

Outputs next to this file: AppIcon-1024.png, mycss-appicon.svg,
MenuIcon.png (72 px, template), mycss-menubar.svg.
The PNGs are committed, so building the app does not need rsvg-convert.
"""
import math, subprocess, pathlib

here = pathlib.Path(__file__).parent

# --- macOS tile: 1024 canvas, 824 squircle, superellipse exponent ~5 ---------
def squircle(cx, cy, half, n=5.0, steps=360):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + half * math.copysign(abs(c) ** (2 / n), c)
        y = cy + half * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M " + " L ".join(pts) + " Z"

TILE = squircle(512, 512, 412)

BODY = "M 28.5 562.5 L 70.5 479.5 C 87.5 444.0 112.6 410.9 118.1 371.0 C 124.2 326.8 98.8 288.2 101.0 244.4 C 104.2 182.6 137.7 178.7 165.8 145.3 C 196.3 109.0 196.2 75.1 255.2 66.7 C 314.4 58.3 346.9 100.3 380.5 140.6 C 402.4 166.8 427.7 186.9 438.0 220.9 C 459.2 290.8 402.9 351.4 334.8 356.0 C 321.9 357.1 308.7 358.3 295.5 359.6 C 285.6 379.9 267.5 414.0 267.5 479.5 L 267.5 562.5 Z"
MOUTH = "M 222.9 285.3 C 231.7 312.8 258.1 350.2 308.7 358.5"

app = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <clipPath id="tile"><path d="{TILE}"/></clipPath>
    <linearGradient id="fill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2A35"/><stop offset="0.55" stop-color="#16161D"/><stop offset="1" stop-color="#0B0B0F"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.6" cy="0.3" r="0.5">
      <stop offset="0" stop-color="#FFD400" stop-opacity="0.13"/><stop offset="1" stop-color="#FFD400" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.13"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.04"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.10"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="22"/><feOffset dy="16" result="b"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <path d="{TILE}" fill="#000" filter="url(#shadow)"/>
  <path d="{TILE}" fill="url(#fill)"/>
  <g clip-path="url(#tile)">
    <rect width="1024" height="1024" fill="url(#glow)"/>
    <g transform="translate(100 100) scale(1.609)" stroke-linejoin="round" stroke-linecap="round" fill="none">
      <path d="{BODY}" stroke="#F7F4E8" stroke-width="12.1"/>
      <path d="{MOUTH}" stroke="#F7F4E8" stroke-width="12.1"/>
      <circle cx="258.1" cy="175.9" r="48.4" stroke="#F7F4E8" stroke-width="11"/>
      <circle cx="275.7" cy="151.7" r="14.3" fill="#FFD400" stroke="none"/>
    </g>
  </g>
  <path d="{TILE}" fill="none" stroke="url(#rim)" stroke-width="3"/>
</svg>'''

# --- menu bar: template image, black on transparent, 18 pt -------------------
# Heavier strokes than the app icon so it holds up at 18 pt. The glint is
# knocked out of the eye, which is what makes it read as an eye.
menu = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="56 36 410 410" width="72" height="72">
  <defs><mask id="m"><rect x="0" y="0" width="512" height="512" fill="#fff"/>
    <circle cx="275.7" cy="151.7" r="17" fill="#000"/></mask></defs>
  <g stroke="#000" stroke-linejoin="round" stroke-linecap="round" fill="none" mask="url(#m)">
    <path d="M 70.5 479.5 C 87.5 444.0 112.6 410.9 118.1 371.0 C 124.2 326.8 98.8 288.2 101.0 244.4 C 104.2 182.6 137.7 178.7 165.8 145.3 C 196.3 109.0 196.2 75.1 255.2 66.7 C 314.4 58.3 346.9 100.3 380.5 140.6 C 402.4 166.8 427.7 186.9 438.0 220.9 C 459.2 290.8 402.9 351.4 334.8 356.0 C 321.9 357.1 308.7 358.3 295.5 359.6 C 285.6 379.9 267.5 414.0 267.5 479.5" stroke-width="34"/>
    <path d="{MOUTH}" stroke-width="34"/>
    <circle cx="258.1" cy="175.9" r="52" fill="#000" stroke="none"/>
  </g>
</svg>'''

(here / "mycss-appicon.svg").write_text(app)
(here / "mycss-menubar.svg").write_text(menu)
subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", str(here / "mycss-appicon.svg"), "-o", str(here / "AppIcon-1024.png")], check=True)
subprocess.run(["rsvg-convert", "-w", "72", "-h", "72", str(here / "mycss-menubar.svg"), "-o", str(here / "MenuIcon.png")], check=True)
# A preview of the menu icon on light and dark bars, 6x, for eyeballing only.
print("ok")
