"""Generates the tutorial pointer arrow: a flat 2D arrow given depth by extruding it along Z.

The silhouette is a plain rectangular shaft on a triangular head, with every corner rounded off
by a small radius so nothing reads as a hard point. Authored tip-down with the tip at the origin,
so the scene positions the point rather than the centre, and only has to scale it.

Run with `python 3DArt/Effects/tutorial_arrow_source.py` from the project root to regenerate
tutorial_arrow.obj after changing any of the numbers below.
"""
import math

# --- silhouette ------------------------------------------------------------------------------
TOTAL_H       = 0.953   # tip to the top of the shaft
HEAD_Y        = 0.480   # where the head's barbs sit, and the shaft starts
HEAD_HALF_W   = 0.250
SHAFT_HALF_W  = 0.085
HALF_DEPTH    = 0.080   # half the thickness of the slab
CORNER_RADIUS = 0.020   # kept small on purpose: enough to take the edge off, no more

ARC_STEPS = 6


def arc(center, start, end, steps):
    cx, cy = center
    a0 = math.atan2(start[1] - cy, start[0] - cx)
    a1 = math.atan2(end[1] - cy, end[0] - cx)
    radius = math.hypot(start[0] - cx, start[1] - cy)
    sweep = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
    return [(cx + radius * math.cos(a0 + sweep * i / steps),
             cy + radius * math.sin(a0 + sweep * i / steps)) for i in range(steps + 1)]


def round_corner(prev_point, corner, next_point, radius, steps):
    """The arc that replaces a corner, tangent to both edges meeting there.

    Works for the reflex corners of the barbs as well: the centre is placed along the bisector of
    the two edge directions, which lands on the correct side either way.
    """
    v1 = (prev_point[0] - corner[0], prev_point[1] - corner[1])
    v2 = (next_point[0] - corner[0], next_point[1] - corner[1])
    l1, l2 = math.hypot(*v1), math.hypot(*v2)
    v1, v2 = (v1[0] / l1, v1[1] / l1), (v2[0] / l2, v2[1] / l2)
    half = math.acos(max(-1.0, min(1.0, v1[0] * v2[0] + v1[1] * v2[1]))) / 2.0
    tangent_dist = radius / math.tan(half)
    t1 = (corner[0] + v1[0] * tangent_dist, corner[1] + v1[1] * tangent_dist)
    t2 = (corner[0] + v2[0] * tangent_dist, corner[1] + v2[1] * tangent_dist)
    bisector = (v1[0] + v2[0], v1[1] + v2[1])
    bl = math.hypot(*bisector)
    bisector = (bisector[0] / bl, bisector[1] / bl)
    center_dist = radius / math.sin(half)
    center = (corner[0] + bisector[0] * center_dist, corner[1] + bisector[1] * center_dist)
    return arc(center, t1, t2, steps)


def build_outline():
    """The arrow as a closed, counter-clockwise loop of points, corners already rounded."""
    corners = [
        (0.0, 0.0),                          # the point
        (HEAD_HALF_W, HEAD_Y),               # right barb
        (SHAFT_HALF_W, HEAD_Y),              # right notch, reflex
        (SHAFT_HALF_W, TOTAL_H),             # top right
        (-SHAFT_HALF_W, TOTAL_H),            # top left
        (-SHAFT_HALF_W, HEAD_Y),             # left notch, reflex
        (-HEAD_HALF_W, HEAD_Y),              # left barb
    ]
    outline = []
    for i, corner in enumerate(corners):
        outline += round_corner(corners[i - 1], corner, corners[(i + 1) % len(corners)],
                                CORNER_RADIUS, ARC_STEPS)

    cleaned = []
    for point in outline:
        if not cleaned or math.dist(point, cleaned[-1]) > 1e-6:
            cleaned.append(point)
    if math.dist(cleaned[0], cleaned[-1]) < 1e-6:
        cleaned.pop()

    area = sum(cleaned[i][0] * cleaned[(i + 1) % len(cleaned)][1]
               - cleaned[(i + 1) % len(cleaned)][0] * cleaned[i][1]
               for i in range(len(cleaned)))
    return cleaned if area > 0 else cleaned[::-1]


def triangulate(points):
    """Ear clipping over a counter-clockwise simple polygon."""
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        d1, d2, d3 = cross(a, b, p), cross(b, c, p), cross(c, a, p)
        return d1 > 1e-12 and d2 > 1e-12 and d3 > 1e-12

    remaining = list(range(len(points)))
    triangles = []
    guard = 0
    while len(remaining) > 3 and guard < 100000:
        guard += 1
        for k in range(len(remaining)):
            i0 = remaining[k - 1]
            i1 = remaining[k]
            i2 = remaining[(k + 1) % len(remaining)]
            a, b, c = points[i0], points[i1], points[i2]
            if cross(a, b, c) <= 1e-12:       # reflex or degenerate, not an ear
                continue
            if any(inside(points[i], a, b, c)
                   for i in remaining if i not in (i0, i1, i2)):
                continue
            triangles.append((i0, i1, i2))
            remaining.pop(k)
            break
        else:
            break
    if len(remaining) == 3:
        triangles.append(tuple(remaining))
    return triangles


def main():
    outline = build_outline()
    count = len(outline)
    cap_triangles = triangulate(outline)

    vertices, normals, uvs, faces = [], [], [], []

    def add(position, normal, uv):
        vertices.append(position)
        normals.append(normal)
        uvs.append(uv)
        return len(vertices)  # obj indices are 1-based

    span_x = 2.0 * HEAD_HALF_W
    front = [add((x, y, HALF_DEPTH), (0.0, 0.0, 1.0),
                 (0.5 + x / span_x, y / TOTAL_H)) for x, y in outline]
    back = [add((x, y, -HALF_DEPTH), (0.0, 0.0, -1.0),
                (0.5 - x / span_x, y / TOTAL_H)) for x, y in outline]

    for a, b, c in cap_triangles:
        faces.append((front[a], front[b], front[c]))
        faces.append((back[a], back[c], back[b]))   # seen from behind, so wound the other way

    # The rim. Its normals come from the outline's own direction, which makes the rounded corners
    # shade as curves while the straight runs between them stay flat.
    rim_front, rim_back = [], []
    for i, (x, y) in enumerate(outline):
        nxt = outline[(i + 1) % count]
        prv = outline[i - 1]
        dx, dy = nxt[0] - prv[0], nxt[1] - prv[1]
        length = math.hypot(dx, dy)
        normal = (dy / length, -dx / length, 0.0)
        rim_front.append(add((x, y, HALF_DEPTH), normal, (i / count, 1.0)))
        rim_back.append(add((x, y, -HALF_DEPTH), normal, (i / count, 0.0)))

    for i in range(count):
        j = (i + 1) % count
        a, b = rim_front[i], rim_front[j]
        c, d = rim_back[j], rim_back[i]
        faces.append((a, c, b))
        faces.append((a, d, c))

    out = ["# Tutorial pointer arrow, generated by tutorial_arrow_source.py",
           "# Flat arrow silhouette extruded along Z, tip down at the origin.", "o TutorialArrow"]
    out += ["v %.6f %.6f %.6f" % v for v in vertices]
    out += ["vt %.6f %.6f" % uv for uv in uvs]
    out += ["vn %.6f %.6f %.6f" % n for n in normals]
    out.append("s 1")
    out += ["f %d/%d/%d %d/%d/%d %d/%d/%d" % (a, a, a, b, b, b, c, c, c) for a, b, c in faces]

    with open("3DArt/Effects/tutorial_arrow.obj", "w", newline="\n") as handle:
        handle.write("\n".join(out) + "\n")

    print("outline points %d, cap tris %d, total tris %d, verts %d"
          % (count, len(cap_triangles), len(faces), len(vertices)))
    print("height %.3f, width %.3f, depth %.3f"
          % (TOTAL_H, 2 * HEAD_HALF_W, 2 * HALF_DEPTH))


main()
