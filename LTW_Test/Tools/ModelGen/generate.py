"""Regenerates the placeholder art the game ships with.

    python Tools/ModelGen/generate.py                everything
    python Tools/ModelGen/generate.py materials      just one stage
    python Tools/ModelGen/generate.py --showcase     plus the review scenes

RUN IT FROM THE PROJECT ROOT. Every output path below is relative to it.

WHY THIS EXISTS. Thirty towers is past the number a person can keep consistent
by hand. A tier ladder only reads if every tower on it obeys the same rules, a
branch only reads as a family if its four tiers really are one shape at four
sizes, and both of those stop being true the first time somebody nudges one
file. So the RULES live in style.py, the numbers live in roster.py, and every
`.tscn` and `.tres` under the folders below is output.

**The output is checked in and is ordinary hand-editable Godot.** Nothing at
runtime knows this tool exists. Tweak a generated file in the editor whenever
that is quicker - just know the next run overwrites it, so anything worth
keeping goes back into the generator.

It writes into:
    Resources/Materials/Towers/     the shared palette
    Resources/UnitStats/Towers/     one BuildingStats per tower
    Resources/Abilities/Towers/     build and upgrade abilities
    Scenes/Units/Towers/            prefabs
    Scenes/Units/Models/Towers/     models
    Scenes/Effects/                 projectiles and impacts

ADDING A ROSTER. The layers are stacked so that only the top one is new work:

    tscn.py       writes Godot's text formats. Never changes
    modelkit.py   primitives, placement, motion. Shared by everything
    style.py      the visual language. A creep roster adds its palette here,
                  next to the tower lines, so the two are chosen together
    <x>_models.py the shapes. This is the real work for a new roster
    <x>_content.py the stats and abilities that point at those models

Elemental towers are the cheap case: same three material roles, same tier
ladder, so they need a palette entry per element and a builder per shape.
Creeps are the bigger one - they need their own model file and their own
content file - but they inherit everything below style.py unchanged.
"""

import sys

import effects
import element_content
import element_models
import materials
import showcase
import tower_content
import tower_models

STAGES = ("materials", "effects", "models", "content")


def run(stages, with_showcase):
    heights = None
    if "materials" in stages:
        materials.generate()
    if "effects" in stages:
        effects.generate()
    if "models" in stages:
        heights = _models()
    if "content" in stages:
        # The prefabs size their health bar and their click box off the model,
        # so content cannot run without the heights models just measured.
        if heights is None:
            heights = _models()
        # The Basic roster LAST, because its build menu has to name the
        # Elemental Core alongside the three 10g towers - and that ability is
        # the elemental content stage's to write.
        element_content.generate(heights)
        tower_content.generate(
            heights, [element_content.build_ability_path("elemental_core")])
    if with_showcase:
        showcase.generate()


def _models():
    """Both rosters' models, and their heights in one dictionary.

    One dictionary rather than two because a KEY is unique across the whole
    game - a tower's files are named by it, and two towers sharing one would
    already have collided on disk long before this.
    """
    heights = tower_models.generate()
    heights.update(element_models.generate())
    print("wrote %d tower models" % len(heights))
    return heights


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    unknown = [a for a in args if a not in STAGES]
    if unknown:
        print("unknown stage(s): %s\nknown: %s" % (", ".join(unknown),
                                                   ", ".join(STAGES)))
        raise SystemExit(2)
    run(args or list(STAGES), "--showcase" in sys.argv[1:])
