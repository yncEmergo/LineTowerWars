"""Every material the tower roster shares.

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
    print("wrote %d tower materials" % count)
