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
    style.py      the visual language. Every roster's palette lives here, next
                  to the others, so they are chosen against each other
    <x>_models.py the shapes. This is the real work for a new roster
    <x>_content.py the stats and abilities that point at those models

All three rosters are in. Elemental towers were the cheap case - same material
roles, same shape of ladder - and creeps were the bigger one, needing their own
shader, their own ladder and a builder per body plan, while still inheriting
every layer below style.py unchanged.

The creep stage writes PREFABS ONLY. Creep stats, passives and pack entries
were authored by hand and unit_data.md 8.1 makes them the authority; see
creep_content.py for why that line is where it is.
"""

import sys

import creep_content
import creep_models
import effects
import element_content
import element_models
import materials
import showcase
import tower_content
import tower_models

STAGES = ("materials", "effects", "models", "content")


def run(stages, with_showcase):
    built = None
    if "materials" in stages:
        materials.generate()
    if "effects" in stages:
        effects.generate()
    if "models" in stages:
        built = _models()
    if "content" in stages:
        # The prefabs size their health bar and their click box off the model,
        # so content cannot run without the dimensions models just measured.
        if built is None:
            built = _models()
        # The Basic roster LAST, because its build menu has to name the
        # Elemental Core alongside the three 10g towers - and that ability is
        # the elemental content stage's to write.
        element_content.generate(built["towers"])
        tower_content.generate(
            built["towers"],
            [element_content.build_ability_path("elemental_core")])
        creep_content.generate(built["creeps"])
    if with_showcase:
        showcase.generate()


def _models():
    """Every roster's models, and what the content stage needs to know about
    them afterwards.

    The two TOWER rosters share one dictionary of heights, because a KEY is
    unique across the whole game - a tower's files are named by it, and two
    towers sharing one would already have collided on disk long before this.

    Creeps are kept apart because what a creep model hands back is a different
    SHAPE of answer: not one number but its height, its click radius, its
    stride and the names of every node that walks. A tower has none of those
    and a creep needs all of them.
    """
    heights = tower_models.generate()
    heights.update(element_models.generate())
    print("wrote %d tower models" % len(heights))
    return {"towers": heights, "creeps": creep_models.generate()}


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    unknown = [a for a in args if a not in STAGES]
    if unknown:
        print("unknown stage(s): %s\nknown: %s" % (", ".join(unknown),
                                                   ", ".join(STAGES)))
        raise SystemExit(2)
    run(args or list(STAGES), "--showcase" in sys.argv[1:])
