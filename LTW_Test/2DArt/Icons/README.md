# Icons - PLACEHOLDER, GENERATED

**Nothing in this folder was drawn.** Every PNG here is a render of the
placeholder primitive model of the unit it names, baked by a kept tool:

    godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- new
    godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- creeps
    godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- wyvern siege_engine

It has to RUN rather than go headless, because baking an image means drawing
one. **`new` is the one to reach for after adding a roster**: it bakes only the
units that have no picture yet, where re-baking a roster whose models have not
moved is a few hundred files of churn nobody asked for. A bare key re-bakes one
unit, which is what to use after tweaking a single model.

What it bakes is SCANNED out of `Resources/UnitStats`, never listed, so a creep
added tomorrow is baked without anybody editing the tool.

**CREEPS ONLY, and that is a rule rather than an omission.** The tower icons
here are named after a tower's DISPLAY NAME - `apprentice.png`, not
`arcane_apprentice.png` - while the tool is keyed by prefab. Pointing it at the
towers bakes a second, parallel set of two hundred files under names nothing
references, which it did once. If the towers ever need re-baking, the naming has
to be settled first.

They exist so a command card is not a grid of blank squares, and they are
expected to be replaced wholesale the moment there is real art - along with
the models they are pictures of. See the tower visual language under
Presentation in game_rules.md for what that art has to say.

Re-running the tool overwrites every file here, so do not edit one by hand
and expect it to survive. One image per unit type, named after its display
name, framed on the unit's own bounding box so every tier comes out the same
size on a card whatever its real height.

## The towers are baked too, and the rule that lets them be

`IconGen3D` used to skip the tower folder entirely. The reason was real: an
icon is looked up by a unit's DISPLAY NAME and written by its KEY, and for the
ELEMENTAL roster those disagree — `apprentice.png` against a key of
`arcane_apprentice` — so baking that folder by key once wrote two hundred files
under names nothing reads.

It is now a CHECK rather than an omission: a unit is baked only where its key
and its display-name slug are the same string. The thirty Basic towers pass
(`lesser_watch_tower` is "Lesser Watch Tower"), the eighty elemental ones do
not, and the run prints each one it skipped and what its icon is really called.

    godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- towers

The Elemental Core passes the same test and is baked with them, which is
correct — it is a tower with no element yet, and its key really is its name.
