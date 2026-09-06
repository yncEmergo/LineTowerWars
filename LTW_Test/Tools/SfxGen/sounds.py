# The sound language of the roster, as data. This is the style.py of this tool.
#
# NONE OF THIS IS A HARD RULE. Every choice in this file was authored by Claude
# rather than decided by the user, who asked for placeholder audio and not for a
# sound design. The rules exist for CONTINUITY - so a tower added later sounds
# like it came from the same game as the ones before it - and where a comment
# here says "always" or "never", read it as: this is what the existing sounds
# were built to, and breaking it for one unit costs the continuity it buys.
#
# What IS worth holding to is that a change goes HERE and is regenerated, so the
# whole set moves together. A hand edit to one generated .wav is overwritten by
# the next run and leaves that one sound the only one disagreeing.
#
# THE THREE AXES, which are deliberately the ones PLACEHOLDER_ART.md already
# uses for the models, because a player should hear the same three answers the
# silhouette gives:
#
#   WHICH LINE     TIMBRE. A physical line is noise through a resonant band -
#                  wood, stone, metal all live in where that band sits. An
#                  arcane line is FM, whose index says how metallic it rings.
#                  Nothing else distinguishes them, and nothing else has to.
#
#   WHICH BRANCH   one changed ingredient, matching the single silhouette
#                  change a branch gets. A pierce branch keeps the body and
#                  sharpens the transient; a blast branch keeps the transient
#                  and adds the low thump.
#
#   WHICH TIER     BRIGHTER AND LONGER, cumulatively. Tier is the one axis a
#                  player reads without being told, because a bigger sound is
#                  the oldest convention there is. See TIER below.
#
# THE ONE RULE WORTH MORE THAN THE OTHERS: nothing in a tower defence gets to
# be long. A shot fires twenty times a second in a full maze, so every fire
# sound here is under 0.2 seconds and every impact under 0.3. An effect that
# outlasts its own rate of fire turns into a drone the moment the maze fills,
# and no amount of mixing afterwards rescues it. Explosions are the exception
# and are rare by design.

import dsp


# How a tier scales a sound: pitch multiplier, length multiplier, extra drive.
# Cumulative in the same way the model rules are - a tier 3 tower is a tier 1
# tower with three steps applied, not a separately authored sound.
TIER = [
    {"pitch": 1.00, "length": 1.00, "drive": 1.0},
    {"pitch": 0.94, "length": 1.12, "drive": 1.4},
    {"pitch": 0.88, "length": 1.25, "drive": 1.9},
    {"pitch": 0.82, "length": 1.40, "drive": 2.5},
]


# --- tower fire ------------------------------------------------------------

def arrow_release(rng):
    """A bow. All transient, no body - the string is the sound.

    The band sweeping DOWN over the burst is what makes it a release rather
    than a hiss: energy leaving, which is what a launch is.
    """
    body = dsp.osc("noise", 0, 0.09, rng)
    body = dsp.band_pass(body, dsp.sweep(4200.0, 1100.0, 0.09), q=2.2)
    body = dsp.apply_env(body, dsp.env_decay(0.09, decay=9.0))

    # The limb thump under it, quiet enough to be felt and not heard.
    thump = dsp.osc("sine", dsp.sweep(220.0, 120.0, 0.09), 0.09)
    thump = dsp.apply_env(thump, dsp.env_decay(0.09, decay=14.0))

    return dsp.finish(dsp.mix(body, dsp.gain(thump, 0.35)))


def bolt_release(rng):
    """A crossbow: the same event with a mechanism around it. Lower, harder,
    and with a click of released catch on the front."""
    click = dsp.osc("noise", 0, 0.012, rng)
    click = dsp.band_pass(click, 2600.0, q=1.4)
    click = dsp.apply_env(click, dsp.env_decay(0.012, decay=16.0))

    body = dsp.osc("noise", 0, 0.11, rng)
    body = dsp.band_pass(body, dsp.sweep(2000.0, 620.0, 0.11), q=3.0)
    body = dsp.apply_env(body, dsp.env_decay(0.11, decay=8.0))

    thump = dsp.osc("square", dsp.sweep(300.0, 150.0, 0.07), 0.07)
    thump = dsp.apply_env(thump, dsp.env_decay(0.07, decay=13.0))
    thump = dsp.low_pass(thump, 900.0)

    return dsp.finish(dsp.mix(click, body, dsp.gain(thump, 0.5)))


def cannon_fire(rng):
    """Powder. A low sine dropping out from under a cracking noise burst -
    the two-part shape every gunshot has, and the reason it reads as a gun
    rather than as a drum."""
    crack = dsp.osc("noise", 0, 0.22, rng)
    crack = dsp.res_low_pass(crack, dsp.sweep(5200.0, 380.0, 0.22), q=1.6)
    crack = dsp.apply_env(crack, dsp.env_decay(0.22, decay=7.0))

    boom = dsp.osc("sine", dsp.sweep(150.0, 46.0, 0.30), 0.30)
    boom = dsp.apply_env(boom, dsp.env_decay(0.30, decay=5.5))

    return dsp.finish(dsp.drive(dsp.mix(crack, dsp.gain(boom, 0.9)), 1.6))


def magic_cast(rng):
    """The arcane counterpart to a bowstring, and the reason fm() exists.

    Index sweeping DOWN means it starts metallic and settles into a tone: a
    thing gathering itself. Sweeping up would be the same ingredients reading
    as a thing coming apart, which is what creep_death uses.
    """
    body = dsp.fm(dsp.sweep(420.0, 780.0, 0.26), 2.51,
                  dsp.sweep(5.5, 0.6, 0.26), 0.26)
    body = dsp.apply_env(body, dsp.env_decay(0.26, decay=5.0, attack=0.012))

    shimmer = dsp.fm(1560.0, 3.02, dsp.sweep(2.0, 0.2, 0.26), 0.26)
    shimmer = dsp.apply_env(shimmer, dsp.env_decay(0.26, decay=8.0, attack=0.02))

    return dsp.finish(dsp.mix(body, dsp.gain(shimmer, 0.28)))


# --- impacts ---------------------------------------------------------------

def impact_flesh(rng):
    """Dull and low. No resonance at all, which is the whole point: a body
    does not ring, and the absence of a band is what separates this from
    every other impact in the set."""
    body = dsp.osc("noise", 0, 0.13, rng)
    body = dsp.low_pass(body, dsp.sweep(1400.0, 300.0, 0.13))
    body = dsp.apply_env(body, dsp.env_decay(0.13, decay=11.0))

    thump = dsp.osc("sine", dsp.sweep(130.0, 62.0, 0.14), 0.14)
    thump = dsp.apply_env(thump, dsp.env_decay(0.14, decay=9.0))

    return dsp.finish(dsp.mix(body, dsp.gain(thump, 0.8)))


def impact_armor(rng):
    """Metal, which means INHARMONIC partials. The ratios below are not a
    scale and are not meant to be - a struck plate has no harmonic series, and
    picking 2.76 and 5.40 rather than 2 and 3 is the entire difference between
    a bell and a beep."""
    ring = dsp.silence(0.24)
    for ratio, level, decay in ((1.00, 1.00, 9.0), (2.76, 0.62, 12.0),
                                (5.40, 0.34, 17.0), (8.93, 0.18, 22.0)):
        partial = dsp.osc("sine", 620.0 * ratio, 0.24)
        partial = dsp.apply_env(partial, dsp.env_decay(0.24, decay=decay))
        ring = dsp.mix(ring, dsp.gain(partial, level))

    strike = dsp.osc("noise", 0, 0.03, rng)
    strike = dsp.band_pass(strike, 3400.0, q=1.2)
    strike = dsp.apply_env(strike, dsp.env_decay(0.03, decay=14.0))

    return dsp.finish(dsp.mix(ring, dsp.gain(strike, 0.75)))


def impact_stone(rng):
    """A single mid band, hard decay. Between flesh and armour on the one axis
    that separates the three: how much the thing struck rings back."""
    body = dsp.osc("noise", 0, 0.10, rng)
    body = dsp.band_pass(body, dsp.sweep(1100.0, 780.0, 0.10), q=3.6)
    body = dsp.apply_env(body, dsp.env_decay(0.10, decay=13.0))

    grit = dsp.osc("noise", 0, 0.10, rng)
    grit = dsp.low_pass(grit, 2600.0)
    grit = dsp.apply_env(grit, dsp.env_decay(0.10, decay=20.0))

    return dsp.finish(dsp.mix(body, dsp.gain(grit, 0.45)))


def explosion(rng):
    """The one long sound in the set, and it earns it by being rare.

    A cutoff falling slowly over most of a second is what an explosion IS -
    the high end leaves first and the low end rolls on. Doing it with the
    envelope alone gives a noise burst that fades, which reads as a wave rather
    than a blast.
    """
    roar = dsp.osc("noise", 0, 0.85, rng)
    roar = dsp.res_low_pass(roar, dsp.sweep(6000.0, 130.0, 0.85), q=1.1)
    roar = dsp.apply_env(roar, dsp.env_decay(0.85, decay=4.2, attack=0.004))

    thump = dsp.osc("sine", dsp.sweep(120.0, 32.0, 0.55), 0.55)
    thump = dsp.apply_env(thump, dsp.env_decay(0.55, decay=4.0))

    crack = dsp.osc("noise", 0, 0.05, rng)
    crack = dsp.high_pass(crack, 2200.0)
    crack = dsp.apply_env(crack, dsp.env_decay(0.05, decay=12.0))

    return dsp.finish(dsp.drive(dsp.mix(roar, dsp.gain(thump, 1.1),
                                        dsp.gain(crack, 0.5)), 1.9))


# --- creeps ----------------------------------------------------------------

def creep_death(rng):
    """Downward everything: pitch, cutoff, amplitude. A thing coming apart is
    the one sound a player must never have to look at the screen to identify,
    because it is the feedback that says the maze is working."""
    body = dsp.osc("saw", dsp.sweep(340.0, 74.0, 0.22), 0.22)
    body = dsp.res_low_pass(body, dsp.sweep(2400.0, 340.0, 0.22), q=2.6)
    body = dsp.apply_env(body, dsp.env_decay(0.22, decay=7.0, attack=0.006))

    squelch = dsp.osc("noise", 0, 0.16, rng)
    squelch = dsp.band_pass(squelch, dsp.sweep(1500.0, 420.0, 0.16), q=2.0)
    squelch = dsp.apply_env(squelch, dsp.env_decay(0.16, decay=10.0))

    return dsp.finish(dsp.mix(body, dsp.gain(squelch, 0.55)))


def creep_spawn(rng):
    """Upward, and deliberately the same ingredients as creep_death run the
    other way. Two sounds that are each other's reverse are a pair a player
    learns in one match without being taught."""
    body = dsp.osc("saw", dsp.sweep(90.0, 300.0, 0.16), 0.16)
    body = dsp.res_low_pass(body, dsp.sweep(400.0, 2000.0, 0.16), q=2.4)
    body = dsp.apply_env(body, dsp.env_ar(0.16, 0.03, 0.09))
    return dsp.finish(dsp.gain(body, 0.8))


# --- match feedback --------------------------------------------------------

def gold_gain(rng):
    """Three rising blips. The only tonal sound in the set, and tonal on
    purpose: money is the one event that should feel like a reward rather than
    like a physical thing happening."""
    voices = []
    for index, freq in enumerate((1046.5, 1318.5, 1568.0)):
        blip = dsp.osc("tri", freq, 0.06)
        blip = dsp.apply_env(blip, dsp.env_decay(0.06, decay=11.0, attack=0.002))
        voices.append(dsp.at(blip, index * 0.045, 0.22))
    return dsp.finish(dsp.mix(*voices))


def build_place(rng):
    """A thunk with weight under it. This is the sound a player hears more than
    any other in a build phase, so it is short, low and completely unmusical -
    anything with a pitch becomes a tune when you place nine towers in a row."""
    thud = dsp.osc("sine", dsp.sweep(190.0, 72.0, 0.20), 0.20)
    thud = dsp.apply_env(thud, dsp.env_decay(0.20, decay=8.0))

    settle = dsp.osc("noise", 0, 0.11, rng)
    settle = dsp.low_pass(settle, dsp.sweep(1800.0, 420.0, 0.11))
    settle = dsp.apply_env(settle, dsp.env_decay(0.11, decay=13.0))

    return dsp.finish(dsp.mix(thud, dsp.gain(settle, 0.5)))


def build_refused(rng):
    """The "no". Bitcrushed on purpose - it is the one sound in the set that is
    allowed to be artificial, because it is the interface talking rather than
    the world, and a player should never mistake it for something in the maze."""
    tone = dsp.osc("square", dsp.sweep(230.0, 150.0, 0.16), 0.16)
    tone = dsp.bitcrush(tone, bits=4, hold=3)
    tone = dsp.low_pass(tone, 1700.0)
    tone = dsp.apply_env(tone, dsp.env_decay(0.16, decay=7.0, attack=0.004))
    return dsp.finish(dsp.gain(tone, 0.7))


def life_lost(rng):
    """A creep reached the end. Low, slow and the longest non-explosion here,
    because it is the only sound that has to cut through whatever else is
    happening and be understood while the player is looking somewhere else."""
    tone = dsp.osc("tri", dsp.sweep(420.0, 118.0, 0.45), 0.45)
    tone = dsp.apply_env(tone, dsp.env_decay(0.45, decay=3.6, attack=0.008))
    tone = dsp.low_pass(tone, 2400.0)

    thud = dsp.osc("sine", dsp.sweep(96.0, 44.0, 0.40), 0.40)
    thud = dsp.apply_env(thud, dsp.env_decay(0.40, decay=5.0))

    return dsp.finish(dsp.mix(tone, dsp.gain(thud, 0.85)))


# THE ROSTER. Category decides the output folder; the name is the file name and
# is also what seeds the sound's noise, so renaming one changes its dice - which
# is a feature when a burst lands badly and the recipe is otherwise right.
ROSTER = [
    ("Towers", "arrow_release", arrow_release),
    ("Towers", "bolt_release", bolt_release),
    ("Towers", "cannon_fire", cannon_fire),
    ("Towers", "magic_cast", magic_cast),
    ("Impacts", "impact_flesh", impact_flesh),
    ("Impacts", "impact_armor", impact_armor),
    ("Impacts", "impact_stone", impact_stone),
    ("Impacts", "explosion", explosion),
    ("Creeps", "creep_death", creep_death),
    ("Creeps", "creep_spawn", creep_spawn),
    ("Match", "gold_gain", gold_gain),
    ("Match", "build_place", build_place),
    ("Match", "build_refused", build_refused),
    ("Match", "life_lost", life_lost),
]
