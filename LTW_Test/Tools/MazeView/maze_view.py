"""Draws a saved maze (a TowerLayout .tres) as text, so a maze can be READ.

A TowerLayout is two parallel arrays of type ids and internal cells, which
nobody can picture. This prints the lane as a grid of two-letter codes with a
legend, and optionally the route a creep would walk through it.

    python Tools/MazeView/maze_view.py Resources/Blueprints/blueprint_4.tres
    python Tools/MazeView/maze_view.py <layout.tres> --path
    python Tools/MazeView/maze_view.py <layout.tres> --path --wide
    python Tools/MazeView/maze_view.py <layout.tres> --path --shape
    python Tools/MazeView/maze_view.py <layout.tres> --holes 10

Run from the project root. Stdlib only, like the rest of Tools/, and nothing
in the game reaches into it.

**The drawing is a reading of the file, never a copy of it.** Documents that
want to show a maze should say which file and how to draw it, rather than
pasting a grid that goes stale the next time the blueprint is saved.

What the grid shows:
- one character per INTERNAL cell, so a tower is a 2 x 2 block of its code and
  a half-cell offset is visible as a one-character shift
- rows are labelled with the PLAYER row of the building area (1 at the top);
  S is the spawn zone, E the end zone
- a position is written the way players write it, (column|row): column in
  player cells from 0 at the left edge, row from 1 at the top, so internal
  cell (5, 34) is (2.5|15)
- a disc's code starts with '*'. Creeps walk over discs
- with --path, '+' marks an approximate creep route
- with --shape, every tower is '#' and every disc 'o', which reads better when
  what matters is the shape rather than which tower stands where
- with --holes N, the N towers whose loss would SHORTEN the route the most, and
  by how much: the positions an attacker (a Phoenix above all) wants to knock
  out, and so the ones a defender protects and repairs first. Same approximate
  route as --path

**The route is an approximation of the game's own, not a copy of it.** It is a
shortest path over internal cells that never squeezes between two towers
touching at a corner, which is the game's rule, but it ignores the line
clearance towers keep and the commit-and-reroute behaviour. Good enough to see
the SHAPE of a maze and to compare two mazes' lengths; not a measurement of
where any creep will be. Flyers ignore the maze and fly straight down.
"""

import heapq
import math
import os
import re
import sys
from glob import glob

SPAWN_ROWS = 6      # internal rows of spawn zone at the top (3 player cells)
END_ROWS = 2        # internal rows of end zone at the bottom (1 player cell)
TOWER = 2           # a tower is 2 x 2 internal cells
TIER_PREFIXES = (("Ultimate ", "u"), ("Greater ", "g"), ("Advanced ", "a"),
                 ("Lesser ", "l"))


def unit_names(root):
    """unit_type_id -> display_name, scanned from every stats resource."""
    names = {}
    pattern = os.path.join(root, "Resources", "UnitStats", "**", "*.tres")
    for path in glob(pattern, recursive=True):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        type_id = re.search(r"^unit_type_id = (\d+)", text, re.M)
        name = re.search(r'^display_name = "([^"]*)"', text, re.M)
        if type_id:
            names[int(type_id.group(1))] = name.group(1) if name else path
    return names


def read_layout(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    ids = re.search(r"unit_type_ids = PackedInt32Array\(([^)]*)\)", text)
    cells = re.search(r"cells = Array\[Vector2i\]\(\[(.*?)\]\)", text, re.S)
    size = re.search(r"grid_size = Vector2i\((\d+), (\d+)\)", text)
    type_ids = [int(v) for v in ids.group(1).split(",") if v.strip()] if ids else []
    points = [(int(x), int(y)) for x, y in
              re.findall(r"Vector2i\((-?\d+), (-?\d+)\)", cells.group(1))] if cells else []
    width, depth = (int(size.group(1)), int(size.group(2))) if size else (16, 68)
    return list(zip(type_ids, points)), width, depth


def assign_codes(type_ids, names):
    """A two-character code per distinct type, stable for one drawing."""
    codes = {}
    used = set()
    for type_id in sorted(set(type_ids)):
        name = names.get(type_id, str(type_id))
        tier = "-"
        base = name
        for prefix, mark in TIER_PREFIXES:
            if base.startswith(prefix):
                base, tier = base[len(prefix):], mark
                break
        is_disc = base.endswith(" Disc")
        letters = [c.upper() for c in base if c.isalpha()]
        code = None
        for letter in letters + [chr(c) for c in range(ord("A"), ord("Z") + 1)]:
            candidate = ("*" + letter) if is_disc else (letter + tier)
            if candidate not in used:
                code = candidate
                break
        used.add(code)
        codes[type_id] = code
    return codes


def route(blocked, width, depth):
    """Shortest spawn-to-end path over internal cells, no corner squeezing."""
    def free(x, y):
        return 0 <= x < width and 0 <= y < depth and (x, y) not in blocked

    dist = {}
    prev = {}
    heap = []
    for x in range(width):
        if free(x, 0):
            dist[(x, 0)] = 0.0
            heapq.heappush(heap, (0.0, (x, 0)))
    steps = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
             (1, 1, math.sqrt(2)), (-1, 1, math.sqrt(2)),
             (1, -1, math.sqrt(2)), (-1, -1, math.sqrt(2))]
    goal = None
    while heap:
        cost, (x, y) = heapq.heappop(heap)
        if cost > dist.get((x, y), math.inf):
            continue
        if y >= depth - END_ROWS:
            goal = (x, y)
            break
        for dx, dy, step in steps:
            nx, ny = x + dx, y + dy
            if not free(nx, ny):
                continue
            if dx and dy and not (free(x + dx, y) and free(x, y + dy)):
                continue
            if cost + step < dist.get((nx, ny), math.inf):
                dist[(nx, ny)] = cost + step
                prev[(nx, ny)] = (x, y)
                heapq.heappush(heap, (cost + step, (nx, ny)))
    if goal is None:
        return None, None
    path = [goal]
    while path[-1] in prev:
        path.append(prev[path[-1]])
    return set(path), dist[goal]


def player_position(cx, cy):
    """A tower's position the way players write it: (column|row).

    The column counts player cells from 0 at the left edge of the lane and the row
    counts from 1 at the top of the building area, matching the grid labels, so a
    tower anchored at internal (5, 34) is (2.5|15).
    """
    return f"({cx / 2:g}|{(cy - SPAWN_ROWS) / 2 + 1:g})"


def row_label(y, depth):
    if y < SPAWN_ROWS:
        return "S"
    if y >= depth - END_ROWS:
        return "E"
    offset = y - SPAWN_ROWS
    return str(offset // 2 + 1) if offset % 2 == 0 else ""


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 1
    show_path = "--path" in argv
    wide = "--wide" in argv
    shape = "--shape" in argv
    holes = 0
    if "--holes" in argv:
        at = argv.index("--holes")
        holes = int(argv[at + 1]) if at + 1 < len(argv) and argv[at + 1].isdigit() else 10
        args = [a for a in args if a != str(holes)]
    root = os.getcwd()
    names = unit_names(root)
    entries, width, depth = read_layout(args[0])
    codes = assign_codes([t for t, _ in entries], names)

    grid = [["." for _ in range(width)] for _ in range(depth)]
    blocked = set()
    for type_id, (cx, cy) in entries:
        code = codes[type_id]
        is_disc = code.startswith("*")
        for dy in range(TOWER):
            for dx in range(TOWER):
                x, y = cx + dx, cy + dy
                if 0 <= x < width and 0 <= y < depth:
                    if shape:
                        grid[y][x] = "o" if is_disc else "#"
                    else:
                        grid[y][x] = code[dx]
                    if not is_disc:
                        blocked.add((x, y))

    length = None
    if show_path:
        cells, length = route(blocked, width, depth)
        if cells:
            for x, y in cells:
                if grid[y][x] == ".":
                    grid[y][x] = "+"

    sep = " " if wide else ""
    print(f"{args[0]}  ({len(entries)} buildings, grid {width}x{depth} internal)")
    print("      " + sep.join(format(x, "x") for x in range(width)))
    for y in range(depth):
        if y in (SPAWN_ROWS, depth - END_ROWS):
            print("      " + sep.join("-" for _ in range(width)))
        print(f"{row_label(y, depth):>4}  " + sep.join(grid[y]))

    print()
    for type_id, code in sorted(codes.items(), key=lambda kv: kv[1]):
        count = sum(1 for t, _ in entries if t == type_id)
        print(f"  {code}  {names.get(type_id, '?'):<32} x{count}")
    if show_path:
        if length is None:
            print("\n  no route: this layout blocks the lane")
        else:
            straight = depth - 1
            print(f"\n  approx route {length / 2:.1f} player cells"
                  f" (straight down would be {straight / 2:.1f})")
    if holes:
        print_holes(entries, codes, names, blocked, width, depth, holes)
    return 0


def print_holes(entries, codes, names, blocked, width, depth, count):
    """Route length lost if each blocking building were destroyed, worst first."""
    _, base = route(blocked, width, depth)
    if base is None:
        print("\n  no route: this layout blocks the lane")
        return
    losses = []
    for type_id, (cx, cy) in entries:
        if codes[type_id].startswith("*"):
            continue
        footprint = {(cx + dx, cy + dy) for dx in range(TOWER) for dy in range(TOWER)}
        _, without = route(blocked - footprint, width, depth)
        if without is not None and base - without > 0.01:
            losses.append((base - without, type_id, cx, cy))
    losses.sort(reverse=True)
    print(f"\n  towers whose loss shortens the route most (route {base / 2:.1f} player cells):")
    for lost, type_id, cx, cy in losses[:count]:
        print(f"    -{lost / 2:5.1f} cells  {codes[type_id]}  {names.get(type_id, '?'):<28}"
              f" at {player_position(cx, cy)}  internal ({cx},{cy})")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
