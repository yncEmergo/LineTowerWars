"""Every material the units of the game share.

Three families, and between them they are the whole palette:

    <line>_plate       one per LINE and TONE - base, deep and pale. The
    <line>_plate_deep  body colour and the rim light. Three depths of the same
    <line>_plate_pale  material, so a tower has parts instead of being a lump
    trim_t<n>          one per PRICE TIER. The iron -> white gold ramp, and the
                       primary thing a player reads a tower's tier off
    energy_<line>_t<n> one per line and tier. The lit accent

The tier is baked into a material rather than overridden per tower because
per-instance shader uniforms do not exist under gl_compatibility - see
tower_energy.gdshader. That is also why there is one energy material per
combination rather than one per line.

Trim is a plain StandardMaterial3D on purpose. What makes an Ultimate read as
one is the COLOUR of its metal, so a 3D artist replacing these primitives
should be able to swap six materials for six real metals without touching a
line of shader code.

The creeps' own three families sit at the bottom of the file and write into
Resources/Materials/Creeps instead. Same five roles, different folder, so
retuning what a creep is made of can never move a tower.

This is the folder to open when the whole game should look different. Nothing
here is per tower: retuning one file moves every tower that uses it.
"""

import io
import os

import style as ts
from tscn import c, num

OUT = "Resources/Materials/Towers"
PLATING = "res://Resources/Shaders/tower_plating.gdshader"
ENERGY = "res://Resources/Shaders/tower_energy.gdshader"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def shader_material(shader_path, params):
    lines = [
        '[gd_resource type="ShaderMaterial" format=3]',
        "",
        '[ext_resource type="Shader" path="%s" id="1_shader"]' % shader_path,
        "",
        "[resource]",
        'shader = ExtResource("1_shader")',
    ]
    for key, value in params:
        lines.append("shader_parameter/%s = %s" % (key, value))
    return "\n".join(lines) + "\n"


def standard_material(params):
    lines = ['[gd_resource type="StandardMaterial3D" format=3]', "", "[resource]"]
    for key, value in params:
        lines.append("%s = %s" % (key, value))
    return "\n".join(lines) + "\n"


def _plate(line, palette, tone):
    plate, dark = palette["tones"][tone]
    suffix = "" if tone == "base" else "_" + tone
    write("%s/%s_plate%s.tres" % (OUT, line, suffix), shader_material(PLATING, [
        ("plate_color", c(plate)),
        ("plate_dark_color", c(dark)),
        ("panel_frequency", num(7.0)),
        ("panel_width", num(0.06)),
        ("panel_strength", num(0.35)),
        ("ambient_wrap", num(0.4)),
        ("rim_color", c(palette["rim"])),
        ("rim_strength", num(0.6)),
        ("rim_power", num(2.6)),
        ("roughness_value", num(0.62)),
        ("metallic_value", num(0.15)),
    ]))


def _trim(index, colour):
    # Only the top two tiers emit at all, so gold reads as hot rather than
    # merely pale when a whole maze of mixed tiers is on screen at once.
    top = index >= 4
    write("%s/trim_t%d.tres" % (OUT, index), standard_material([
        ("albedo_color", c(colour)),
        ("metallic", num(0.9)),
        ("metallic_specular", num(0.75)),
        ("roughness", num(0.45 - 0.06 * index)),
        ("emission_enabled", "true" if top else "false"),
        ("emission", c(colour)),
        ("emission_energy_multiplier", num(0.25 if index == 4 else 0.55)),
    ]))


def _energy(line, palette, index):
    write("%s/energy_%s_t%d.tres" % (OUT, line, index), shader_material(ENERGY, [
        ("glow_color", c(palette["glow"])),
        ("dim_color", c(palette["dim"])),
        ("tier", num(ts.energy_tier(index))),
        ("min_brightness", num(0.55)),
        ("max_brightness", num(2.3)),
        ("min_pulse_speed", num(0.55)),
        ("max_pulse_speed", num(2.6)),
        ("pulse_depth", num(0.35)),
        ("surge_tier_start", num(0.45)),
        ("surge_speed", num(0.9)),
        ("surge_width", num(0.22)),
        ("surge_strength", num(0.9)),
        ("surge_height", num(1.0)),
        ("facet_strength", num(0.3)),
    ]))


def _stone(element, palette, tone):
    """One tone of one ELEMENT's material.

    The same plating shader the Basic lines use, with two differences that
    matter: the colour is allowed to carry the element's hue, and the panel
    lines are scaled by the element's own `facets`, so an organic element -
    Void, Unholy, Water, Primal - is not streaked with the panel seams that
    make a Basic tower read as machinery. See style.ELEMENTS.
    """
    plate, dark = palette["tones"][tone]
    facets = palette.get("facets", 1.0)
    suffix = "" if tone == "base" else "_" + tone
    write("%s/%s_stone%s.tres" % (OUT, element, suffix), shader_material(PLATING, [
        ("plate_color", c(plate)),
        ("plate_dark_color", c(dark)),
        ("panel_frequency", num(7.0)),
        ("panel_width", num(0.06)),
        ("panel_strength", num(round(0.35 * facets, 4))),
        ("ambient_wrap", num(0.4)),
        ("rim_color", c(palette["rim"])),
        ("rim_strength", num(0.6)),
        ("rim_power", num(2.6)),
        ("roughness_value", num(0.62)),
        ("metallic_value", num(0.15)),
    ]))


def _element_energy(element, palette, index):
    """One element's lit accent at one tier.

    Brighter at its FLOOR than a Basic line's is, because the accent IS the
    element on most of these towers where on a Basic tower it is a small warm
    detail on grey stone.

    Its CEILING is deliberately not much higher, and that was found the hard
    way: pushed to 3.1 every Ultimate's accent saturated to white, so an
    Ultimate Doom Guard and an Ultimate Lich glowed the same colour and the
    element - the one thing this roster spends that the Basic one cannot - was
    gone at exactly the tier a player has paid the most for it.
    """
    write("%s/energy_%s_t%d.tres" % (OUT, element, index),
          shader_material(ENERGY, [
              ("glow_color", c(palette["glow"])),
              ("dim_color", c(palette["dim"])),
              ("tier", num(ts.element_energy_tier(index))),
              ("min_brightness", num(0.85)),
              ("max_brightness", num(2.15)),
              ("min_pulse_speed", num(0.55)),
              ("max_pulse_speed", num(2.6)),
              ("pulse_depth", num(0.35)),
              ("surge_tier_start", num(0.35)),
              ("surge_speed", num(0.9)),
              ("surge_width", num(0.22)),
              ("surge_strength", num(0.9)),
              ("surge_height", num(1.0)),
              ("facet_strength", num(0.3)),
          ]))


def _elements():
    """Every element's materials, and the Elemental Core's alongside them.

    The Core is handed the same treatment as an element without being one: it
    is the tower with no element yet, so it needs the same five roles and must
    never be iterated as an eleventh entry in ELEMENTS.
    """
    count = 0
    palettes = dict(ts.ELEMENTS)
    palettes["core"] = ts.ELEMENTAL_CORE
    for element, palette in palettes.items():
        for tone in ts.TONES:
            _stone(element, palette, tone)
            count += 1
        for index in range(len(ts.ELEMENT_PRICE_TIERS)):
            _element_energy(element, palette, index)
            count += 1
    return count


# ============================================================================
# CREEPS
# ============================================================================
#
# The creep roster's own palette, in its own folder, for the same reason the
# two tower rosters keep separate style entries: retuning what a creep is made
# of should never be able to move a tower.
#
# Three families again, and they map one for one onto the five material roles
# modelkit names, which is the whole reason those roles are named for what they
# DO rather than for what a tower has:
#
#     <creep>_hide       body   the bulk of the creature
#     <creep>_hide_deep  deep   undersides, bellies, the shadowed half
#     <creep>_hide_pale  pale   heads, backs, anything catching light
#     carapace_r<n>      trim   claws, horns, plates, weapons. One per RUNG
#     eye_r<n>           glow   eyes, and an attacker's lit weapon edge. Ditto
#
# The two ramps are per RUNG rather than per creep on purpose: they are the
# ladder, and a ladder only reads if every creep on the same rung wears exactly
# the same metal.

CREEP_OUT = "Resources/Materials/Creeps"
HIDE = "res://Resources/Shaders/creep_hide.gdshader"
VAPOUR = "res://Resources/Shaders/creep_vapour.gdshader"

# How solid each tone of a FLYING creep is drawn. The pale tone is its head and
# its shoulders and should be the part a player actually sees; the deep tone is
# whatever trails off it and should be nearly gone.
VAPOUR_OPACITY = {"base": 0.85, "deep": 0.62, "pale": 1.0}

# How strongly each tone bands. The pale tone is nearly smooth because it is
# usually the head, and a head with ribs on it reads as a mistake.
BAND_SCALE = {"base": 1.0, "deep": 0.8, "pale": 0.45}

# How much sheen each tone carries. Undersides catch no light worth the name.
SHEEN_SCALE = {"base": 1.0, "deep": 0.45, "pale": 1.25}


def _hide(creep, palette, tone):
    """One tone of one GROUND creep's body."""
    plate, dark = palette["tones"][tone]
    bands = palette.get("bands", 0.6)
    suffix = "" if tone == "base" else "_" + tone
    write("%s/%s_hide%s.tres" % (CREEP_OUT, creep, suffix),
          shader_material(HIDE, [
              ("hide_color", c(plate)),
              ("hide_dark_color", c(dark)),
              ("band_frequency", num(9.0)),
              ("band_strength", num(round(0.34 * bands * BAND_SCALE[tone], 4))),
              ("band_axis", "Vector3(0, 1, 0)"),
              ("ambient_wrap", num(0.55)),
              ("sheen_strength", num(round(0.30 * SHEEN_SCALE[tone], 4))),
              ("rim_color", c(palette["rim"])),
              ("rim_strength", num(0.7)),
              ("rim_power", num(2.4)),
              ("roughness_value", num(0.82)),
          ]))


def _vapour(creep, palette, tone):
    """One tone of one FLYING creep's body.

    Same three tones, same file names, so a model builder never has to know
    which of the two shaders it is being handed - which is what lets one
    `wraith` builder be reused by any flyer the roster grows.
    """
    plate, dark = palette["tones"][tone]
    bands = palette.get("bands", 0.3)
    suffix = "" if tone == "base" else "_" + tone
    write("%s/%s_hide%s.tres" % (CREEP_OUT, creep, suffix),
          shader_material(VAPOUR, [
              ("vapour_color", c(plate)),
              ("vapour_deep_color", c(dark)),
              ("rim_color", c(palette["rim"])),
              ("face_alpha", num(0.22)),
              ("edge_alpha", num(0.92)),
              ("edge_power", num(2.2)),
              ("opacity", num(VAPOUR_OPACITY[tone])),
              ("band_frequency", num(6.0)),
              ("band_strength", num(round(0.9 * bands + 0.15, 4))),
              ("band_drift", num(0.35)),
          ]))


def _carapace(rung, entry):
    """One rung of the hard-parts ramp: bone through blackened steel.

    A plain StandardMaterial3D for exactly the reason the tower trim is one -
    what makes a rung read is the COLOUR of the material, so an artist should
    be able to swap six of these for six real ones without touching a shader.
    """
    colour, metallic, roughness = entry
    top = rung >= len(ts.CREEP_CARAPACE_RAMP) - 1
    write("%s/carapace_r%d.tres" % (CREEP_OUT, rung), standard_material([
        ("albedo_color", c(colour)),
        ("metallic", num(metallic)),
        ("metallic_specular", num(0.4 + 0.35 * metallic)),
        ("roughness", num(roughness)),
        # Only the very top rung is hot, and barely. Anything more and the
        # carapace starts competing with the eyes, which are the roster's one
        # lit signal and the only thing that may ramp brightness.
        ("emission_enabled", "true" if top else "false"),
        ("emission", c((0.55, 0.20, 0.12))),
        ("emission_energy_multiplier", num(0.35)),
    ]))


def _eye(rung, colour):
    """One rung of the eye ramp, and an attacker's lit weapon edge.

    UNSHADED, so an eye is the same brightness whichever way the creep is
    facing and whatever the sun is doing. A lit dot that dims when the creature
    turns away is a dot the player stops trusting.
    """
    write("%s/eye_r%d.tres" % (CREEP_OUT, rung), standard_material([
        ("shading_mode", "0"),
        ("albedo_color", c(colour)),
    ]))


def _creeps():
    import creep_roster as cr

    count = 0
    for key, palette in ts.CREEPS.items():
        for tone in ts.TONES:
            if cr.is_flying(key):
                _vapour(key, palette, tone)
            else:
                _hide(key, palette, tone)
            count += 1

    for rung, entry in enumerate(ts.CREEP_CARAPACE_RAMP):
        _carapace(rung, entry)
        count += 1
    for rung, colour in enumerate(ts.CREEP_EYE_RAMP):
        _eye(rung, colour)
        count += 1
    return count


def generate():
    count = 0
    for line, palette in ts.LINES.items():
        for tone in ts.TONES:
            _plate(line, palette, tone)
            count += 1
        for index in range(len(ts.PRICE_TIERS)):
            _energy(line, palette, index)
            count += 1

    for index, colour in enumerate(ts.TRIM_RAMP):
        _trim(index, colour)
        count += 1

    count += _elements()
    count += _creeps()
    print("wrote %d unit materials" % count)
