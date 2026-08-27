# A tiny supersampled rasteriser, enough to draw flat silhouettes.
#
# Every glyph is authored in a 0..64 square, the size the icon is written at,
# so a stroke width in glyphs.py is the number of pixels it really comes out
# as. The mask underneath is SS times that in each direction and holds one
# byte per sample; downsampling a block of them to one alpha value is where
# the antialiasing comes from, which is the same soft edge the hand made
# stat_*.png icons have.
#
# Coverage is 1 bit per sample on purpose. Overlapping shapes then union
# cleanly - a hammer head laid over its handle is one solid silhouette, not a
# brighter patch where the two met - and erase() punches a hole that is
# exactly as clean.

import math

## Samples per pixel along each axis. 8 gives 64 levels of edge coverage,
## past what an eye can pick out of a white-on-dark glyph.
SS = 8

## Canvas the glyphs are authored in, and the size they are written at.
SIZE = 64


def round_rect_points(x, y, w, h, r, steps=8):
    """A rounded rectangle as a point list, so a glyph can rotate one.

    Handed out rather than kept private because a hammer is a rounded head on
    a rounded handle, tilted, and a tilted round_rect is the only way to draw
    that without the tool growing a transform stack.
    """
    r = min(r, w * 0.5, h * 0.5)
    if r <= 0.0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    corners = [
        (x + w - r, y + h - r, 0.0),
        (x + r, y + h - r, 90.0),
        (x + r, y + r, 180.0),
        (x + w - r, y + r, 270.0),
    ]
    for cx, cy, start in corners:
        for i in range(steps + 1):
            a = math.radians(start + i * 90.0 / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


class Mask:
    """A 1 bit coverage buffer at SS times icon resolution."""

    def __init__(self, size=SIZE, ss=SS):
        self.size = size
        self.ss = ss
        self.n = size * ss
        self.buf = bytearray(self.n * self.n)

    # -- spans ------------------------------------------------------------

    def _span(self, yi, xa, xb, value):
        """Fills sample row yi between two sample-space x coordinates."""
        if yi < 0 or yi >= self.n:
            return
        # A sample counts when its CENTRE is inside the span, which is what
        # keeps two shapes sharing an edge from overlapping by a sample.
        x0 = max(0, int(math.floor(xa - 0.5)) + 1)
        x1 = min(self.n - 1, int(math.ceil(xb - 0.5)) - 1)
        if x1 < x0:
            return
        row = yi * self.n
        self.buf[row + x0:row + x1 + 1] = bytes([value]) * (x1 - x0 + 1)

    # -- primitives -------------------------------------------------------

    def polygon(self, points, value=1):
        """Even-odd scanline fill. Points are in icon space, closed for you."""
        pts = [(x * self.ss, y * self.ss) for x, y in points]
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        top = max(0, int(math.floor(min(ys))))
        bottom = min(self.n - 1, int(math.ceil(max(ys))))
        for yi in range(top, bottom + 1):
            yc = yi + 0.5
            crossings = []
            for i in range(len(pts)):
                x0, y0 = pts[i]
                x1, y1 = pts[(i + 1) % len(pts)]
                if (y0 <= yc) != (y1 <= yc):
                    crossings.append(x0 + (yc - y0) / (y1 - y0) * (x1 - x0))
            crossings.sort()
            for i in range(0, len(crossings) - 1, 2):
                self._span(yi, crossings[i], crossings[i + 1], value)

    def circle(self, cx, cy, r, value=1):
        cx, cy, r = cx * self.ss, cy * self.ss, r * self.ss
        top = max(0, int(math.floor(cy - r)))
        bottom = min(self.n - 1, int(math.ceil(cy + r)))
        for yi in range(top, bottom + 1):
            dy = yi + 0.5 - cy
            if abs(dy) > r:
                continue
            dx = math.sqrt(r * r - dy * dy)
            self._span(yi, cx - dx, cx + dx, value)

    def ring(self, cx, cy, r, width, value=1):
        """An annulus drawn in one pass, so it never erases what it sits on."""
        inner = max(0.0, r - width)
        cx, cy = cx * self.ss, cy * self.ss
        ro, ri = r * self.ss, inner * self.ss
        top = max(0, int(math.floor(cy - ro)))
        bottom = min(self.n - 1, int(math.ceil(cy + ro)))
        for yi in range(top, bottom + 1):
            dy = yi + 0.5 - cy
            if abs(dy) > ro:
                continue
            dxo = math.sqrt(ro * ro - dy * dy)
            if abs(dy) < ri:
                dxi = math.sqrt(ri * ri - dy * dy)
                self._span(yi, cx - dxo, cx - dxi, value)
                self._span(yi, cx + dxi, cx + dxo, value)
            else:
                self._span(yi, cx - dxo, cx + dxo, value)

    def rect(self, x, y, w, h, value=1):
        self.polygon([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], value)

    def round_rect(self, x, y, w, h, r, value=1):
        self.polygon(round_rect_points(x, y, w, h, r), value)

    def capsule(self, p0, p1, width, value=1, round_caps=True):
        """A thick line. The workhorse: most strokes in glyphs.py are one."""
        (x0, y0), (x1, y1) = p0, p1
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        if length < 1e-6:
            if round_caps:
                self.circle(x0, y0, width * 0.5, value)
            return
        nx, ny = -dy / length * width * 0.5, dx / length * width * 0.5
        self.polygon(
            [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny),
             (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)],
            value,
        )
        if round_caps:
            self.circle(x0, y0, width * 0.5, value)
            self.circle(x1, y1, width * 0.5, value)

    def polyline(self, points, width, value=1):
        """A chain of capsules. The round caps double as the joints."""
        for i in range(len(points) - 1):
            self.capsule(points[i], points[i + 1], width, value)

    def arc(self, cx, cy, r, width, start_deg, end_deg, value=1, steps=64):
        """A stroked arc, built as one closed strip so it stays a single fill."""
        outer, inner = r, max(0.0, r - width)
        pts = []
        for i in range(steps + 1):
            a = math.radians(start_deg + (end_deg - start_deg) * i / steps)
            pts.append((cx + outer * math.cos(a), cy + outer * math.sin(a)))
        for i in range(steps, -1, -1):
            a = math.radians(start_deg + (end_deg - start_deg) * i / steps)
            pts.append((cx + inner * math.cos(a), cy + inner * math.sin(a)))
        self.polygon(pts, value)

    # -- erasing ----------------------------------------------------------

    def erase(self, shape, *args, **kwargs):
        """Punches a hole: the same primitives, drawn as 0.

        Called as erase(self.circle, cx, cy, r), which saves the list above
        from needing a cut-out twin of every entry in it.
        """
        kwargs["value"] = 0
        shape(*args, **kwargs)

    # -- output -----------------------------------------------------------

    def bbox(self):
        """Icon-space bounds of what has been drawn, or None if nothing has."""
        left, top, right, bottom = self.n, self.n, -1, -1
        for yi in range(self.n):
            row = self.buf[yi * self.n:(yi + 1) * self.n]
            if 1 not in row:
                continue
            top = min(top, yi)
            bottom = max(bottom, yi)
            left = min(left, row.index(1))
            right = max(right, self.n - 1 - row[::-1].index(1))
        if bottom < 0:
            return None
        return (left / self.ss, top / self.ss,
                (right + 1) / self.ss, (bottom + 1) / self.ss)

    def to_alpha(self):
        """Box-filters the sample buffer down to one alpha byte per pixel."""
        ss, n, size = self.ss, self.n, self.size
        area = ss * ss
        rows = []
        for y in range(size):
            row = bytearray(size)
            for x in range(size):
                total = 0
                for j in range(ss):
                    base = (y * ss + j) * n + x * ss
                    total += sum(self.buf[base:base + ss])
                row[x] = (total * 255 + area // 2) // area
            rows.append(row)
        return rows
