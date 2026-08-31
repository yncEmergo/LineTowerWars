# Small helpers for writing .tscn and .tres by hand, in the shapes CLAUDE.md
# asks for: no invented uids, ext_resources referenced by path only, and every
# property written after the script line.

import math


def c(v):
    """A Color literal, opaque."""
    return "Color(%s, %s, %s, 1)" % (num(v[0]), num(v[1]), num(v[2]))


def num(v):
    if isinstance(v, int):
        return str(v)
    text = ("%.4f" % v).rstrip("0").rstrip(".")
    return text if text not in ("", "-") else "0"


def t3(x=0.0, y=0.0, z=0.0, rx=0.0, ry=0.0, rz=0.0, scale=1.0):
    """Transform3D from an euler rotation in radians, then a scale.

    `scale` is a single number for a uniform one, or an (x, y, z) triple for a
    per-LOCAL-AXIS one - which is how a round primitive is squashed into
    something lopsided without authoring a mesh for every lump. It scales the
    basis columns, so it happens in the part's own space and a rotated part
    still stretches along the axis it was authored on.
    """
    if not isinstance(scale, (tuple, list)):
        scale = (scale, scale, scale)
    bx = [1.0, 0.0, 0.0]
    by = [0.0, 1.0, 0.0]
    bz = [0.0, 0.0, 1.0]

    def rot(basis, axis, a):
        if a == 0.0:
            return basis
        ca, sa = math.cos(a), math.sin(a)
        out = []
        for v in basis:
            if axis == "x":
                out.append([v[0], v[1] * ca - v[2] * sa, v[1] * sa + v[2] * ca])
            elif axis == "y":
                out.append([v[0] * ca + v[2] * sa, v[1], -v[0] * sa + v[2] * ca])
            else:
                out.append([v[0] * ca - v[1] * sa, v[0] * sa + v[1] * ca, v[2]])
        return out

    basis = [bx, by, bz]
    basis = rot(basis, "x", rx)
    basis = rot(basis, "y", ry)
    basis = rot(basis, "z", rz)
    basis = [[v * scale[i] for v in col] for i, col in enumerate(basis)]

    # Godot's .tscn Transform3D() takes the basis ROW BY ROW, while `basis`
    # above is built as the three column vectors. Writing the columns straight
    # out transposes the matrix, which for a rotation is its inverse - every
    # authored angle comes out negated. That put the Cannon's mortar tube
    # underground and aimed the anti-air rack at the floor, so it is worth the
    # transpose being explicit here rather than being fixed by flipping signs
    # at forty call sites.
    rows = [
        basis[0][0], basis[1][0], basis[2][0],
        basis[0][1], basis[1][1], basis[2][1],
        basis[0][2], basis[1][2], basis[2][2],
    ]
    return "Transform3D(%s)" % ", ".join(num(v) for v in rows + [x, y, z])


class Scene:
    """Accumulates ext_resources, sub_resources and nodes, then renders."""

    def __init__(self):
        self._ext = []
        self._ext_ids = {}
        self._sub = []
        self._sub_names = set()
        self._nodes = []

    def ext(self, kind, path):
        if path in self._ext_ids:
            return self._ext_ids[path]
        rid = "%d_%s" % (len(self._ext) + 1, path.get_stem() if False else _stem(path))
        self._ext.append((kind, path, rid))
        self._ext_ids[path] = rid
        return rid

    def sub(self, kind, name, lines):
        if name in self._sub_names:
            return name
        self._sub_names.add(name)
        self._sub.append((kind, name, lines))
        return name

    def node(self, name, kind=None, parent=".", instance=None, props=None,
             node_paths=None, script=None):
        self._nodes.append({
            "name": name, "type": kind, "parent": parent, "instance": instance,
            "props": props or [], "node_paths": node_paths, "script": script,
        })

    def render(self, header):
        out = [header, ""]
        for kind, path, rid in self._ext:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
        if self._ext:
            out.append("")
        for kind, name, lines in self._sub:
            out.append('[sub_resource type="%s" id="%s"]' % (kind, name))
            out.extend(lines)
            out.append("")
        for n in self._nodes:
            head = '[node name="%s"' % n["name"]
            if n["type"]:
                head += ' type="%s"' % n["type"]
            if n["parent"] != ".":
                head += ' parent="%s"' % n["parent"]
            elif self._nodes.index(n) != 0:
                head += ' parent="."'
            if n["instance"]:
                head += ' instance=ExtResource("%s")' % n["instance"]
            if n["node_paths"]:
                head += ' node_paths=PackedStringArray(%s)' % ", ".join(
                    '"%s"' % p for p in n["node_paths"])
            head += "]"
            out.append(head)
            if n["script"]:
                out.append('script = ExtResource("%s")' % n["script"])
            out.extend(n["props"])
            out.append("")
        return "\n".join(out).rstrip() + "\n"


def _stem(path):
    stem = path.rsplit("/", 1)[-1]
    stem = stem.rsplit(".", 1)[0]
    return "".join(ch if ch.isalnum() else "_" for ch in stem)
