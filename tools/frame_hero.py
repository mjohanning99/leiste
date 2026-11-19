#!/usr/bin/env python3
"""Makes the README's top picture from a screenshot of the bar alone
(docs/screenshots/bar.png): the plain grey desktop it was taken on is extended
above it, so the bar sits on an empty desktop without showing anyone's own.
Needs Pillow. python3 tools/frame_hero.py"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bar = Image.open(os.path.join(ROOT, 'docs/screenshots/bar.png')).convert('RGB')
w, h = bar.size
grey = bar.getpixel((w // 2, 0))	# the desktop's own colour, just above the bar

# The screen's rounded corners came out black, also in the gaps between the
# islands. Fill every black area that touches the picture's edge with the
# desktop's grey (black inside an icon doesn't touch the edge, so it stays).
px = bar.load()
edge = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
for x, y in edge:
	if px[x, y] == (0, 0, 0):
		ImageDraw.floodfill(bar, (x, y), grey, thresh=12)

above, below = 380, 24
hero = Image.new('RGB', (w, h + above + below), grey)
hero.paste(bar, (0, above))
hero = hero.resize((2400, round((h + above + below) * 2400 / w)), Image.LANCZOS)

# Rounded corners, so it reads as a picture of a screen.
mask = Image.new('L', hero.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, *hero.size), radius=28, fill=255)
out = Image.new('RGBA', hero.size, (0, 0, 0, 0))
out.paste(hero, (0, 0), mask)
out.save(os.path.join(ROOT, 'docs/screenshots/hero.png'), optimize=True)
print('docs/screenshots/hero.png', out.size)
