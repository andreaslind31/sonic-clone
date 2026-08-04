#!/usr/bin/env python3
"""Scale sprites up onto a checkerboard so generated art can be eyeballed.

    python3 tools/preview.py out.png 4 assets/sprites/player.png ...
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio


def main():
    out, scale = sys.argv[1], int(sys.argv[2])
    images = [pngio.read(p) for p in sys.argv[3:]]
    width = max(i.shape[1] for i in images) * scale
    height = sum(i.shape[0] for i in images) * scale + (len(images) - 1) * 8
    canvas = np.zeros((height, width, 4), np.uint8)
    for y in range(height):  # checkerboard so transparency reads
        for x in range(0, width, 8):
            tone = 90 if ((x // 8) + (y // 8)) % 2 == 0 else 130
            canvas[y, x : x + 8] = (tone, tone, tone, 255)

    y = 0
    for img in images:
        big = np.repeat(np.repeat(img, scale, axis=0), scale, axis=1)
        mask = big[..., 3] > 0
        region = canvas[y : y + big.shape[0], 0 : big.shape[1]]
        region[mask] = big[mask]
        y += big.shape[0] + 8
    pngio.write(out, canvas)
    print(f"wrote {out} ({width}x{height})")


if __name__ == "__main__":
    main()
