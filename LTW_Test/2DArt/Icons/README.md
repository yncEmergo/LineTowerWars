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
