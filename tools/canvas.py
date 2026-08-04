"""Tiny pixel drawing surface used by the asset generators."""

import numpy as np


class Canvas:
    def __init__(self, width, height):
        self.w = width
        self.h = height
        self.a = np.zeros((height, width, 4), np.uint8)

    # --- primitives ---------------------------------------------------------
    def px(self, x, y, colour):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = (*colour, 255) if len(colour) == 3 else colour

    def rect(self, x0, y0, x1, y1, colour):
        for y in range(int(round(y0)), int(round(y1)) + 1):
            for x in range(int(round(x0)), int(round(x1)) + 1):
                self.px(x, y, colour)

    def ellipse(self, cx, cy, rx, ry, colour):
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                dx = (x - cx) / rx
                dy = (y - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self.px(x, y, colour)

    def disc(self, cx, cy, r, colour):
        self.ellipse(cx, cy, r, r, colour)

    def ring(self, cx, cy, r_outer, r_inner, colour, a0=None, a1=None):
        """Filled annulus, optionally limited to the arc between two angles."""
        for y in range(int(cy - r_outer - 1), int(cy + r_outer + 2)):
            for x in range(int(cx - r_outer - 1), int(cx + r_outer + 2)):
                d = np.hypot(x - cx, y - cy)
                if not (r_inner <= d <= r_outer):
                    continue
                if a0 is not None:
                    ang = np.degrees(np.arctan2(y - cy, x - cx)) % 360
                    lo, hi = a0 % 360, a1 % 360
                    inside = lo <= ang <= hi if lo <= hi else (ang >= lo or ang <= hi)
                    if not inside:
                        continue
                self.px(x, y, colour)

    def poly(self, points, colour):
        ys = [p[1] for p in points]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            spans = []
            n = len(points)
            for i in range(n):
                x0, y0 = points[i]
                x1, y1 = points[(i + 1) % n]
                if y0 == y1:
                    continue
                if min(y0, y1) <= y < max(y0, y1):
                    spans.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
            spans.sort()
            for i in range(0, len(spans) - 1, 2):
                self.rect(spans[i], y, spans[i + 1], y, colour)

    def line(self, x0, y0, x1, y1, colour, width=1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(steps + 1):
            t = i / steps
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            if width <= 1:
                self.px(x, y, colour)
            else:
                self.disc(x, y, width / 2.0, colour)

    def capsule(self, x0, y0, x1, y1, r, colour):
        self.line(x0, y0, x1, y1, colour, width=r * 2)

    # --- passes -------------------------------------------------------------
    def outline(self, colour, only_outside=True):
        """Add a 1px border around every opaque cluster."""
        alpha = self.a[..., 3] > 0
        pad = np.pad(alpha, 1)
        neighbours = (
            pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
        )
        target = neighbours & ~alpha if only_outside else neighbours
        self.a[target] = (*colour, 255)

    def shade(self, colour, dy=1):
        """Darken the bottom edge of each opaque cluster for cheap volume."""
        alpha = self.a[..., 3] > 0
        below_empty = np.zeros_like(alpha)
        below_empty[:-dy] = ~alpha[dy:]
        below_empty[-dy:] = True
        self.a[alpha & below_empty] = (*colour, 255)

    def flip_h(self):
        out = Canvas(self.w, self.h)
        out.a = self.a[:, ::-1].copy()
        return out

    def blit(self, src, x, y, alpha_only=False):
        sh, sw = src.shape[:2]
        x, y = int(x), int(y)
        x0, y0 = max(0, x), max(0, y)
        x1, y1 = min(self.w, x + sw), min(self.h, y + sh)
        if x0 >= x1 or y0 >= y1:
            return
        patch = src[y0 - y : y1 - y, x0 - x : x1 - x]
        dst = self.a[y0:y1, x0:x1]
        mask = patch[..., 3] > 0
        if alpha_only:
            mask &= dst[..., 3] == 0
        dst[mask] = patch[mask]


def sheet(frames, columns=None):
    """Pack equally sized canvases into one horizontal (or grid) spritesheet."""
    fw, fh = frames[0].w, frames[0].h
    columns = columns or len(frames)
    rows = (len(frames) + columns - 1) // columns
    out = np.zeros((rows * fh, columns * fw, 4), np.uint8)
    for i, frame in enumerate(frames):
        cx, cy = (i % columns) * fw, (i // columns) * fh
        out[cy : cy + fh, cx : cx + fw] = frame.a
    return out
