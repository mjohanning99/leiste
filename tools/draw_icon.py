#!/usr/bin/env python3
"""Draws Leiste's app icon: a soft evening sky, two windows and the glass bar
along the bottom with its buttons, the one in front raised. Writes
Resources/icon.svg and Resources/Leiste.icns (needs rsvg-convert and macOS's
iconutil). Run it from anywhere: python3 tools/draw_icon.py"""
import os
import shutil
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'Resources')

# Apple's icon grid: a 1024 canvas, the body 824 wide with 100 around it.
B, S, R = 100, 824, 185


def svg():
	bar_y, bar_h = B + 600, 120
	pill = lambda x, w, fill, stroke='none': (f'<rect x="{x}" y="{bar_y + 22}" width="{w}" height="{bar_h - 44}" rx="{(bar_h - 44) / 2}" '
											  f'fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
	return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
	<linearGradient id="sky" x1="0" y1="0" x2="0.35" y2="1">
		<stop offset="0" stop-color="#f7cfa8"/><stop offset="0.45" stop-color="#c9a3d8"/><stop offset="1" stop-color="#6f8fd6"/>
	</linearGradient>
	<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
		<stop offset="0" stop-color="#ffffff" stop-opacity="0.78"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.52"/>
	</linearGradient>
	<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
		<stop offset="0" stop-color="#ffffff" stop-opacity="1"/><stop offset="0.4" stop-color="#ffffff" stop-opacity="0.2"/>
		<stop offset="0.7" stop-color="#ffffff" stop-opacity="0.2"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.9"/>
	</linearGradient>
	<filter id="soft" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#2a1f4a" flood-opacity="0.28"/></filter>
	<clipPath id="body"><rect x="{B}" y="{B}" width="{S}" height="{S}" rx="{R}"/></clipPath>
</defs>
<g clip-path="url(#body)">
	<rect x="{B}" y="{B}" width="{S}" height="{S}" fill="url(#sky)"/>
	<circle cx="{B + 610}" cy="{B + 220}" r="90" fill="#fff4dc" opacity="0.55"/>
	<!-- two windows -->
	<g filter="url(#soft)">
		<rect x="{B + 90}" y="{B + 150}" width="420" height="330" rx="34" fill="#fbfbfd"/>
		<rect x="{B + 90}" y="{B + 150}" width="420" height="58" rx="34" fill="#ececf1"/>
		<rect x="{B + 90}" y="{B + 180}" width="420" height="28" fill="#ececf1"/>
		<circle cx="{B + 130}" cy="{B + 180}" r="11" fill="#ff5f57"/><circle cx="{B + 163}" cy="{B + 180}" r="11" fill="#febc2e"/><circle cx="{B + 196}" cy="{B + 180}" r="11" fill="#28c840"/>
		<rect x="{B + 300}" y="{B + 260}" width="420" height="300" rx="34" fill="#ffffff"/>
		<rect x="{B + 300}" y="{B + 260}" width="420" height="58" rx="34" fill="#efeff4"/>
		<rect x="{B + 300}" y="{B + 290}" width="420" height="28" fill="#efeff4"/>
		<circle cx="{B + 340}" cy="{B + 290}" r="11" fill="#ff5f57"/><circle cx="{B + 373}" cy="{B + 290}" r="11" fill="#febc2e"/><circle cx="{B + 406}" cy="{B + 290}" r="11" fill="#28c840"/>
		<rect x="{B + 340}" y="{B + 350}" width="250" height="18" rx="9" fill="#d9d9e3"/>
		<rect x="{B + 340}" y="{B + 386}" width="320" height="18" rx="9" fill="#e4e4ec"/>
		<rect x="{B + 340}" y="{B + 422}" width="200" height="18" rx="9" fill="#e4e4ec"/>
	</g>
	<!-- the bar: glass with a bright rim, three window buttons, the first raised -->
	<g filter="url(#soft)">
		<rect x="{B + 60}" y="{bar_y}" width="{S - 120}" height="{bar_h}" rx="{bar_h / 2}" fill="url(#glass)"/>
	</g>
	<rect x="{B + 61}" y="{bar_y + 1}" width="{S - 122}" height="{bar_h - 2}" rx="{bar_h / 2 - 1}" fill="none" stroke="url(#rim)" stroke-width="3"/>
	{pill(B + 90, 230, '#ffffff', '#00000014')}
	<rect x="{B + 112}" y="{bar_y + 42}" width="36" height="36" rx="9" fill="#6f8fd6"/>
	<rect x="{B + 162}" y="{bar_y + 52}" width="130" height="16" rx="8" fill="#3a3550" opacity="0.75"/>
	<rect x="{B + 342}" y="{bar_y + 42}" width="36" height="36" rx="9" fill="#e59a6b"/>
	<rect x="{B + 392}" y="{bar_y + 52}" width="100" height="16" rx="8" fill="#3a3550" opacity="0.4"/>
	<rect x="{B + 535}" y="{bar_y + 40}" width="2" height="40" fill="#3a3550" opacity="0.18"/>
	<rect x="{B + 565}" y="{bar_y + 42}" width="36" height="36" rx="9" fill="#9a7ad0"/>
	<rect x="{B + 615}" y="{bar_y + 52}" width="70" height="16" rx="8" fill="#3a3550" opacity="0.4"/>
</g>
</svg>
'''


def main():
	path = os.path.join(RES, 'icon.svg')
	with open(path, 'w') as f:
		f.write(svg())
	work = tempfile.mkdtemp()
	iconset = os.path.join(work, 'Leiste.iconset')
	os.mkdir(iconset)
	for size in (16, 32, 128, 256, 512):
		for scale in (1, 2):
			px = size * scale
			name = f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png'
			subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px), path, '-o', os.path.join(iconset, name)], check=True)
	subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', os.path.join(RES, 'Leiste.icns')], check=True)
	subprocess.run(['rsvg-convert', '-w', '256', '-h', '256', path, '-o', os.path.join(ROOT, 'docs', 'icon.png')], check=True)
	shutil.rmtree(work)
	print('Resources/Leiste.icns and docs/icon.png')


if __name__ == '__main__':
	main()
