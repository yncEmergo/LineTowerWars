# Writes PNGs. Two of them: the icons themselves, which are 8 bit RGBA with
# every pixel white and the whole picture carried in the alpha channel, and
# the opaque review sheet.
#
# Hand rolled rather than Pillow because ModelGen next door needs nothing but
# Python 3, and one tool under Tools/ asking for a pip install would end that.
# A PNG this plain is small enough to write straight: one IHDR, one IDAT of
# zlib-deflated scanlines, one IEND.

import struct
import zlib


def _chunk(tag, payload):
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def write_rgba(path, rgba_rows, width):
    """Writes rows of packed RGBA bytes, one row per scanline."""
    raw = bytearray()
    for row in rgba_rows:
        # Filter type 0, none. These images are mostly flat runs already and
        # the icons land around half a kilobyte, so a filter would buy little.
        raw.append(0)
        raw += row

    header = struct.pack(">IIBBBBB", width, len(rgba_rows), 8, 6, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(data)


def write_white(path, alpha_rows):
    """An icon: white everywhere, shaped entirely by its alpha.

    RGB stays 255 even where alpha is 0. A transparent pixel has no colour of
    its own, so anything else there would bleed out as a dark fringe the
    moment something filters the texture.
    """
    rows = []
    for alpha in alpha_rows:
        row = bytearray()
        for a in alpha:
            row += b"\xff\xff\xff"
            row.append(a)
        rows.append(row)
    write_rgba(path, rows, len(alpha_rows[0]))


def write_over(path, alpha_rows, width, background):
    """White composited over an opaque background, for looking at the result.

    Only the review sheet uses this. An icon is judged on the dark panel it
    will actually be drawn on, never on whatever an image viewer puts behind
    a transparent PNG.
    """
    br, bg, bb = background
    rows = []
    for alpha in alpha_rows:
        row = bytearray()
        for a in alpha:
            row += bytes((br + (255 - br) * a // 255,
                          bg + (255 - bg) * a // 255,
                          bb + (255 - bb) * a // 255, 255))
        rows.append(row)
    write_rgba(path, rows, width)
