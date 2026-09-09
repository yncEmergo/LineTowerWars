"""Every material the units of the game share.

Three families, and between them they are the whole palette:

    timber_t<n>        the Basic roster's three surfaces, one file per PRICE
    masonry_t<n>       TIER and TONE. A Basic tower is timber and turns to
    iron_t<n>          stone as it is bought up, and the Cutter line is iron
                       throughout - so the tier is read off the MATERIAL, and
                       these are indexed by tier rather than by line
    paint_<line>_t<n>  the matte accent, one per LINE and tier, and the only
                       colour the Basic roster carries. None at 10g
    energy_<line>_t<n> one per line and tier. The small lit accent

THERE IS NO `trim_t<n>` AND NO `<line>_plate` ANY MORE, and both are worth
knowing about because they were the roster's whole identity until they were
not. The metal ramp WAS the Basic tier ladder - a ring, a collar, bolts, fins
and a halo in iron through white gold - and it came off for the two reasons the
elemental roster's own metal came off, which are written out in style.py under
THE TIER LADDER. The one plate material per line went with it, because a tower
that turns from wood into stone needs its material to belong to the TIER rather
than to the line.

The elemental roster has three of its own, and the split is the point: an
element's tier is read off its OWN MATERIAL rather than off a metal, because
metal was the loudest thing on every one of those towers and made thirty of
them read as one. See style.py, THE PATH LADDER.

    <element>_stone       the base pair's three tones, as authored
    <element>_stone_t<n>  the same three, moved onto a PATH TIER's rung of the
                          value ramp. This is what trim_t<n> is for the Basic
                          roster, in the element's own hue
    element_ring_t<n>     the only metal an elemental tower wears, and only its
                          200g and 800g towers do. Two rungs, deliberately as
                          far apart as two metals get

The tier is baked into a material rather than overridden per tower because
per-instance shader uniforms do not exist under gl_compatibility - see
tower_energy.gdshader. That is also why there is one energy material per
combination rather than one per line.

The elemental ring metals are plain StandardMaterial3Ds on purpose. What
makes one of those two rungs read is the COLOUR of the metal, so a 3D artist
replacing these primitives should be able to swap them for two real metals
without touching a line of shader code.

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
# The Basic roster's three surfaces and its accent. The elemental roster still
# goes through PLATING, which is why that one is still here: the two rosters
# were separated when the Basic one stopped being made of plate.
TIMBER = "res://Resources/Shaders/tower_timber.gdshader"
MASONRY = "res://Resources/Shaders/tower_masonry.gdshader"
IRON = "res://Resources/Shaders/tower_iron.gdshader"
PAINT = "res://Resources/Shaders/tower_paint.gdshader"


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


def _timber(tone, ti):
    """One tone of the Basic roster's timber, on one rung of its tier ramp.

    Boards get FINER as the ladder climbs - narrower planks, tighter grain -
    which is the quiet half of the tier tell that the tint is the loud half of.
    Rough wide palisade boards at 10g, sawn and fitted joinery by the top.
    """
    tones = ts.basic_surface("timber", tone, ti)
    write("%s/timber_t%d%s.tres" % (OUT, ti, _suffix(tone)),
          shader_material(TIMBER, [
              ("timber_color", c(tones["mid"])),
              ("timber_dark_color", c(tones["dark"])),
              ("timber_light_color", c(tones["light"])),
              ("plank_width", num(round(0.105 - 0.008 * ti, 4))),
              ("seam_width", num(round(0.085 - 0.005 * ti, 4))),
              ("seam_strength", num(0.9)),
              ("plank_variation", num(round(0.56 - 0.03 * ti, 4))),
              ("grain_frequency", num(round(28.0 + 3.5 * ti, 4))),
              ("grain_strength", num(round(0.34 - 0.02 * ti, 4))),
              ("grain_wander", num(round(0.42 - 0.04 * ti, 4))),
              ("damp_height", num(0.26)),
              ("damp_strength", num(0.38)),
              ("ambient_wrap", num(0.4)),
              ("rim_color", c(ts.BASIC_SURFACES["timber"]["rim"])),
              ("rim_strength", num(0.55)),
              ("rim_power", num(2.6)),
              ("roughness_value", num(0.8)),
              ("metallic_value", num(0.0)),
          ]))


def _masonry(tone, ti):
    """One tone of the Basic roster's stone, on one rung of its tier ramp.

    The blocks get BIGGER and the joints get TIGHTER up the ladder - rubble
    coursing at 150g through to dressed ashlar at 25,000g - which is the same
    trick the timber plays and for the same reason: a tint alone is one signal,
    and two neighbouring rungs of any tint ramp are the hardest pair to tell
    apart. A block size is readable where a five percent value step is not.
    """
    tones = ts.basic_surface("masonry", tone, ti)
    write("%s/masonry_t%d%s.tres" % (OUT, ti, _suffix(tone)),
          shader_material(MASONRY, [
              ("stone_color", c(tones["mid"])),
              ("stone_dark_color", c(tones["dark"])),
              ("stone_light_color", c(tones["light"])),
              ("course_height", num(round(0.085 + 0.011 * ti, 4))),
              ("block_length", num(round(0.15 + 0.022 * ti, 4))),
              ("joint_width", num(round(0.075 - 0.007 * ti, 4))),
              ("joint_strength", num(0.7)),
              # RISING with the tier, where it used to fall. The tint
              # ramp now takes an Ultimate's stone down by about 60%,
              # and a darker palette needs a WIDER scatter to show the
              # same coursing - the eye reads contrast, not absolute
              # values. Falling variation on a falling palette made the
              # blocks vanish twice over.
              ("block_variation", num(round(0.52 + 0.06 * ti, 4))),
              ("block_grain", num(round(0.22 + 0.02 * ti, 4))),
              ("damp_height", num(0.34)),
              # EASED OFF AS THE STONE DARKENS. This is a mix TOWARDS the
              # dark tone, so it compounds with the tint ramp - at a fixed
              # 0.42 the foot of an Ultimate went to flat black, which is
              # exactly the thing the ramp stops short of on purpose.
              ("damp_strength", num(round(0.42 - 0.05 * ti, 4))),
              ("ambient_wrap", num(0.4)),
              ("rim_color", c(ts.BASIC_SURFACES["masonry"]["rim"])),
              ("rim_strength", num(0.55)),
              ("rim_power", num(2.6)),
              ("roughness_value", num(0.86)),
              ("metallic_value", num(0.0)),
          ]))


def _iron(tone, ti):
    """One tone of the Basic roster's metal, on one rung of its tier ramp.

    `polish` is the Cutter line's whole tier tell and does most of the work
    here: it lifts the sheen, tightens the brushing and takes the casting pits
    away, so a Lesser Cutter is rough dark castings and an Ultimate Carver is
    bright worked steel. See tower_iron.gdshader for why none of that is
    allowed to be actual METALLIC.
    """
    tones = ts.basic_surface("iron", tone, ti)
    polish = ts.basic_polish(ti)
    write("%s/iron_t%d%s.tres" % (OUT, ti, _suffix(tone)),
          shader_material(IRON, [
              ("iron_color", c(tones["mid"])),
              ("iron_dark_color", c(tones["dark"])),
              ("iron_light_color", c(tones["light"])),
              ("polish", num(polish)),
              ("streak_frequency", num(round(70.0 + 26.0 * polish, 4))),
              ("streak_strength", num(0.28)),
              ("pitting", num(0.35)),
              # WELL DOWN from where this started. The band is additive
              # on top of an already pale tone, and at 0.42 every barrel
              # and blade on the roster came out as a white blob with no
              # shape left in it - the same saturate-to-white failure the
              # elemental accents hit, reached through a highlight rather
              # than through an emission.
              ("sheen_strength", num(round(0.16 + 0.14 * polish, 4))),
              ("sheen_width", num(round(2.2 - 0.9 * polish, 4))),
              ("ambient_wrap", num(0.34)),
              ("rim_color", c(ts.METAL_RIM)),
              ("rim_strength", num(0.45)),
              ("rim_power", num(4.2)),
              ("roughness_value", num(0.42)),
              # Well below 1 whatever the finish, or gl_compatibility renders
              # it black - see tower_iron.gdshader and the creep carapace,
              # which paid for this lesson first.
              ("metallic_value", num(0.35)),
          ]))


def _paint(line, ti):
    """One line's matte accent at one tier. Nothing at all at 10g.

    NO EMISSION, EVER. That is the single rule keeping this off the elements'
    territory: an elemental accent is lit, a painted board is not, and two
    colours can then share a hue without ever being confused. See
    tower_paint.gdshader.
    """
    tones = ts.basic_paint(line, ti)
    if tones is None:
        return False
    write("%s/paint_%s_t%d.tres" % (OUT, line, ti), shader_material(PAINT, [
        ("paint_color", c(tones[0])),
        ("paint_dark_color", c(tones[1])),
        ("weave_frequency", num(150.0)),
        ("weave_strength", num(0.18)),
        # Freshly painted at the top of the ladder, scrubbed and faded at the
        # bottom of it. The one place the paint's own age says the tier.
        ("wear_strength", num(round(0.46 - 0.06 * ti, 4))),
        ("ambient_wrap", num(0.45)),
        ("rim_strength", num(0.45)),
        ("rim_power", num(2.4)),
        ("roughness_value", num(0.92)),
    ]))
    return True


def _suffix(tone):
    return "" if tone == "base" else "_" + tone


def _energy(line, palette, index):
    """One line's lit accent at one tier.

    A line may carry a `glow_ramp` - six colours, one per price tier - instead
    of a single `glow`, and then the accent's HUE is part of the tier ladder
    rather than only its brightness. Exactly one line does: the Sentry, whose
    orb is the biggest object on the model and so the strongest tell it has.
    See style.LINES.
    """
    ramp = palette.get("glow_ramp")
    glow = palette["glow"] if ramp is None else ramp[index]
    write("%s/energy_%s_t%d.tres" % (OUT, line, index), shader_material(ENERGY, [
        ("glow_color", c(glow)),
        ("dim_color", c(palette["dim"])),
        ("tier", num(ts.energy_tier(index))),
        ("min_brightness", num(0.5)),
        # 1.45, DOWN FROM 2.3, and the reason is the Sentry line's
        # rework rather than anything wrong with the number before. The
        # old ceiling was chosen when every Basic accent was a small warm
        # detail on grey stone - a sight, a vent, a spark - where it read
        # as hot and was exactly right. The Sentry line now carries an ORB
        # that is the biggest single object on the model, and at 2.3 an
        # Ultimate Defender was a featureless white ball with no shape and
        # no hue in it, from the one camera angle the game is played at.
        #
        # It is the same trap the elemental roster paid for - see
        # PLACEHOLDER_ART.md - reached from the other direction: there a
        # ceiling tuned for small accents blew up big ones, and here a
        # roster that had only small accents grew a big one.
        ("max_brightness", num(1.45)),
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


def _element_ring(index, colour):
    """One rung of the base pair's ring metal, and the only metal an elemental
    tower is allowed. See style.ELEMENT_RING_RAMP for why there are two of them
    and why they are as far apart as they are.

    The brass rung EMITS, faintly, and the iron one does not. That is what
    makes the 800g ring read as a bright band in the shadow a maze casts over
    itself rather than merely as a paler grey, spent on the one step in this
    roster that has to carry a whole upgrade on its own.
    """
    top = index >= 1
    write("%s/element_ring_t%d.tres" % (OUT, index), standard_material([
        ("albedo_color", c(colour)),
        ("metallic", num(0.85)),
        ("metallic_specular", num(0.5 + 0.3 * index)),
        ("roughness", num(0.52 - 0.22 * index)),
        ("emission_enabled", "true" if top else "false"),
        ("emission", c(colour)),
        ("emission_energy_multiplier", num(0.35)),
    ]))


def _stone(element, palette, tone, ti=None):
    """One tone of one ELEMENT's material.

    The same plating shader the Basic lines use, with two differences that
    matter: the colour is allowed to carry the element's hue, and the panel
    lines are scaled by the element's own `facets`, so an organic element -
    Void, Unholy, Water, Primal - is not streaked with the panel seams that
    make a Basic tower read as machinery. See style.ELEMENTS.

    `ti` names a PATH TIER, and then the authored colour is moved onto that
    tier's rung of PATH_TONE_RAMP before it is written. Those three files are
    what the elemental roster reads its tier off now that its towers carry no
    metal - one value ramp on the element's own material. The Basic roster
    has since been rebuilt around exactly the same idea, in timber, stone and
    iron rather than in one hue; see style.py, THE TIER LADDER. The base pair
    passes None and takes the palette exactly as authored.
    """
    plate, dark = palette["tones"][tone]
    if ti is not None:
        plate = ts.element_path_tone(plate, ti)
        dark = ts.element_path_tone(dark, ti)
    facets = palette.get("facets", 1.0)
    suffix = ts.element_stone_suffix(0 if ti is None else ti)
    suffix += "" if tone == "base" else "_" + tone
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
    Ultimate Moonbeam and an Ultimate Lich glowed the same colour and the
    element - the one thing this roster spends that the Basic one cannot - was
    gone at exactly the tier a player has paid the most for it.
    """
    _energy_material("energy_%s_t%d" % (element, index),
                     palette["glow"], palette["dim"], index)


def _path_energy(path, index, glow, dim):
    """One PATH's own accent at one tier, for the part of its model that claims
    a colour the element does not have. See style.PATH_ACCENTS.

    Written through the same shader and the same tier ramp as an element's, so
    the only thing a path accent changes is the hue: it still brightens, pulses
    and surges exactly as everything else lit on that tower does.
    """
    _energy_material("energy_path_%s_t%d" % (path, index), glow, dim, index)


def _energy_material(file_stem, glow, dim, index):
    write("%s/%s.tres" % (OUT, file_stem),
          shader_material(ENERGY, [
              ("glow_color", c(glow)),
              ("dim_color", c(dim)),
              ("tier", num(ts.element_energy_tier(index))),
              ("min_brightness", num(0.85)),
              # 1.7, not the Basic roster's 2.3 and not the 2.15 this shipped
              # with. The whole point of clipping white at the top of that ramp
              # is that an overcharged tower READS as overcharged, and it works
              # on a Basic tower whose accent is a small warm detail on grey
              # stone. On an elemental tower the accent is often the biggest
              # object on the model - an orb, a rift, a core - and at 2.15 a
              # third of the roster's Ultimates came out as white balls with no
              # hue in them at all. The element is worth more than the clip.
              ("max_brightness", num(1.7)),
              # A THIRD of the Basic roster's rate, at both ends of the ladder,
              # and the surge slowed with it. An elemental tower wears its
              # accent as its BODY - a Firelord is a pool, a heart and six
              # plumes, all of it lit - so the same pulse that reads as a warm
              # detail flickering on a grey Basic tower reads as the whole
              # model blinking, and a maze of them reads as a fault. What the
              # ramp still buys at this rate is the thing it was for: an
              # Ultimate breathes visibly faster than a Lesser. What it stops
              # buying is a tower that demands to be looked at while nothing is
              # happening to it.
              ("min_pulse_speed", num(0.18)),
              ("max_pulse_speed", num(0.85)),
              ("pulse_depth", num(0.35)),
              ("surge_tier_start", num(0.35)),
              # Slowed on the same grounds, and it matters more here than the
              # pulse does: the band is authored against a full model height
              # and most lit pieces are far shorter than one, so it does not
              # CLIMB a plume - it switches the whole plume on and off. At this
              # rate that reads as something turning over inside the tower.
              ("surge_speed", num(0.3)),
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
    path_tiers = [ti for ti in range(len(ts.ELEMENT_PRICE_TIERS))
                  if ts.element_stone_suffix(ti)]
    for element, palette in palettes.items():
        for tone in ts.TONES:
            _stone(element, palette, tone)
            count += 1
            # The Core is a 200g tower and nothing else - it is the ABSENCE of
            # an element, and it morphs rather than upgrading - so it has no
            # path tiers and writing it three rungs of a ladder it can never
            # stand on would leave nine files nothing ever loads.
            if element == "core":
                continue
            for ti in path_tiers:
                _stone(element, palette, tone, ti)
                count += 1
        for index in range(len(ts.ELEMENT_PRICE_TIERS)):
            _element_energy(element, palette, index)
            count += 1
    for index, colour in enumerate(ts.ELEMENT_RING_RAMP):
        _element_ring(index, colour)
        count += 1
    for path, tiers in ts.PATH_ACCENTS.items():
        for index, (glow, dim) in sorted(tiers.items()):
            _path_energy(path, index, glow, dim)
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
    # HOW DENSE the ghost is, and it is per creep because it is the only lever
    # that changes a vapour creep's VALUE. The shader mixes both the colour and
    # the alpha towards the rim by the same fresnel term, so a wraith's
    # interior is nearly clear and reads as whatever is behind it - which means
    # authoring darker body tones does almost nothing on its own. Raising this
    # is what makes one ghost darker than another.
    face = palette.get("face_alpha", 0.22)
    suffix = "" if tone == "base" else "_" + tone
    write("%s/%s_hide%s.tres" % (CREEP_OUT, creep, suffix),
          shader_material(VAPOUR, [
              ("vapour_color", c(plate)),
              ("vapour_deep_color", c(dark)),
              ("rim_color", c(palette["rim"])),
              ("face_alpha", num(face)),
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
        #
        # 0.35 was too much and nothing showed it until a creep actually stood
        # on this rung: a flat plate catching the sun came out salmon pink, and
        # every claw and horn on the first tier 3 creep read as rusted iron
        # rather than as blackened steel. Nothing below rung 5 changes.
        ("emission_enabled", "true" if top else "false"),
        ("emission", c((0.55, 0.20, 0.12))),
        ("emission_energy_multiplier", num(0.16)),
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
            # The WRAITH plan's answer rather than the AIR family's: a solid
            # flyer is opaque. See creep_roster.is_vapour.
            if cr.is_vapour(key):
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


def _basic():
    """The Basic roster's materials.

    THREE SURFACES SHARED BY EVERY LINE and one accent per line, which is the
    reversal this roster went through: it used to be one plate material per
    LINE and one metal per TIER, and it is now one set of surfaces per TIER
    that all three lines draw from. The tier moved from the metal onto the
    material itself, so the files are indexed by tier rather than by line.
    See style.py, THE TIER LADDER.
    """
    count = 0
    for ti in range(len(ts.PRICE_TIERS)):
        for tone in ts.TONES:
            _timber(tone, ti)
            _masonry(tone, ti)
            _iron(tone, ti)
            count += 3
    for line, palette in ts.LINES.items():
        for ti in range(len(ts.PRICE_TIERS)):
            if _paint(line, ti):
                count += 1
            _energy(line, palette, ti)
            count += 1
    return count


def generate():
    count = _basic()
    count += _elements()
    count += _creeps()
    print("wrote %d unit materials" % count)
