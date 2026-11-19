#!/usr/bin/env python3
"""Compares two folders of bar pictures pixel by pixel (from tools/snapshots.sh)
and prints which differ and by how much. Needs Pillow.
python3 tools/compare.py /tmp/before /tmp/after"""
import os
import sys
from PIL import Image, ImageChops

a, b = sys.argv[1], sys.argv[2]
same = True
for name in sorted(os.listdir(a)):
	pa, pb = os.path.join(a, name), os.path.join(b, name)
	if not os.path.exists(pb):
		print(f'{name}: missing afterwards'); same = False; continue
	ia, ib = Image.open(pa).convert('RGBA'), Image.open(pb).convert('RGBA')
	if ia.size != ib.size:
		print(f'{name}: size {ia.size} -> {ib.size}'); same = False; continue
	diff = ImageChops.difference(ia, ib)
	box = diff.getbbox()
	if box:
		changed = sum(1 for p in diff.getdata() if max(p) > 8)
		print(f'{name}: differs in {box}, {changed} pixels clearly changed'); same = False
	else:
		print(f'{name}: identical')
print('ALL IDENTICAL' if same else 'DIFFERENCES FOUND')
