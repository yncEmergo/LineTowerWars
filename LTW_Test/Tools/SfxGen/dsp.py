# The synthesis primitives every sound in sounds.py is built from.
#
# This is the raster.py of this tool: no sound of its own, only the parts. A
# buffer is a plain Python list of floats nominally in -1..1, and every function
# here takes one and returns a new one rather than editing in place, so a recipe
# reads as a chain and an intermediate can be reused.
#
# WHY THE PARTS ARE THESE PARTS. They are sfxr's, near enough: oscillators, a
# decay envelope, a filter with resonance, and a little distortion. That set is
# what makes a sound read as an ARROW or an EXPLOSION rather than as a beep,
# and it is small enough to hold in your head while tuning. Anything richer -
# convolution, physical modelling - buys realism that placeholder audio has no
# use for and costs the ability to change a sound by editing one number.
#
# EVERY RANDOM SOURCE IS SEEDED BY ITS CALLER. Nothing in here touches the
# global `random` module, because a generator whose output changes run to run
# cannot be checked in: `git status` after a run has to say what your edit did
# and nothing else. See generate.py.

import math

from wav import SAMPLE_RATE


# --- lengths and buffers ---------------------------------------------------

def n_samples(duration):
    return max(1, int(round(duration * SAMPLE_RATE)))


def silence(duration):
    return [0.0] * n_samples(duration)


def _as_series(value, count):
    """A float or a per-sample list, always returned as a per-sample list.

    Every parameter that can sweep takes either, so a recipe writes a constant
    as a number and only reaches for sweep() when it actually wants movement.
    """
    if isinstance(value, (int, float)):
        return [float(value)] * count
    if len(value) == count:
        return list(value)
    # Resampled by nearest neighbour, so an envelope built at one length can
    # drive a buffer of another without the caller matching them up by hand.
    out = []
    last = len(value) - 1
    for i in range(count):
        out.append(float(value[min(last, int(i * len(value) / count))]))
    return out


# --- envelopes -------------------------------------------------------------

def sweep(start, end, duration, curve="exp"):
    """A value moving from start to end over duration, per sample.

    EXPONENTIAL BY DEFAULT, because this mostly drives frequency and pitch is
    heard logarithmically: a linear sweep from 800 Hz to 100 Hz spends most of
    its time in the bottom octave and reads as a thud with a click on the front,
    which is rarely what was wanted.
    """
    count = n_samples(duration)
    out = []
    for i in range(count):
        t = i / max(1, count - 1)
        if curve == "exp" and start > 0.0 and end > 0.0:
            out.append(start * math.pow(end / start, t))
        elif curve == "cosine":
            out.append(start + (end - start) * (1.0 - math.cos(t * math.pi)) * 0.5)
        else:
            out.append(start + (end - start) * t)
    return out


def env_decay(duration, decay=6.0, attack=0.003):
    """The percussive envelope: near-instant rise, exponential fall.

    ATTACK IS NOT OPTIONAL even though it is nearly zero. A buffer that starts
    at full amplitude starts with a step, and a step is a click - audible, and
    the first thing that makes generated audio sound broken rather than cheap.
    Three milliseconds is inaudible as an attack and removes it completely.
    """
    count = n_samples(duration)
    rise = max(1, n_samples(attack))
    out = []
    for i in range(count):
        t = i / max(1, count - 1)
        amp = math.exp(-decay * t)
        if i < rise:
            amp *= i / rise
        out.append(amp)
    return out


def env_ar(duration, attack, release):
    """Attack then release, for anything that swells rather than hits."""
    count = n_samples(duration)
    rise = max(1, n_samples(attack))
    fall = max(1, n_samples(release))
    out = []
    for i in range(count):
        if i < rise:
            out.append(i / rise)
        elif i > count - fall:
            out.append(max(0.0, (count - i) / fall))
        else:
            out.append(1.0)
    return out


def apply_env(buffer, envelope):
    series = _as_series(envelope, len(buffer))
    return [buffer[i] * series[i] for i in range(len(buffer))]


# --- oscillators -----------------------------------------------------------

def osc(shape, freq, duration, rng=None, phase=0.0):
    """One oscillator. `freq` is a number or a per-sample series from sweep()."""
    count = n_samples(duration)
    freqs = _as_series(freq, count)
    out = []
    step = 1.0 / SAMPLE_RATE

    if shape == "noise":
        # White noise ignores frequency entirely; it is here so a recipe can
        # name every source the same way.
        return [rng.uniform(-1.0, 1.0) for _ in range(count)]

    for i in range(count):
        phase += freqs[i] * step
        p = phase - math.floor(phase)
        if shape == "sine":
            out.append(math.sin(p * math.tau))
        elif shape == "square":
            out.append(1.0 if p < 0.5 else -1.0)
        elif shape == "saw":
            out.append(2.0 * p - 1.0)
        elif shape == "tri":
            out.append(4.0 * abs(p - 0.5) - 1.0)
        else:
            raise ValueError("unknown oscillator shape: %s" % shape)
    return out


def fm(carrier, ratio, index, duration, rng=None):
    """Frequency modulation: one sine bending another.

    Two oscillators and one number (`index`, which may sweep) buy the whole
    metallic-to-bell range that additive synthesis needs a dozen partials for.
    This is what every magical sound in the roster is made of.
    """
    count = n_samples(duration)
    carriers = _as_series(carrier, count)
    indices = _as_series(index, count)
    out = []
    phase = 0.0
    mod_phase = 0.0
    step = 1.0 / SAMPLE_RATE
    for i in range(count):
        mod_phase += carriers[i] * ratio * step
        modulation = math.sin(mod_phase * math.tau) * indices[i]
        phase += carriers[i] * step
        out.append(math.sin((phase + modulation) * math.tau))
    return out


# --- filters ---------------------------------------------------------------

def low_pass(buffer, cutoff):
    """One pole low pass. Cheap, gentle, no resonance. The workhorse."""
    cutoffs = _as_series(cutoff, len(buffer))
    out = []
    state = 0.0
    for i in range(len(buffer)):
        alpha = 1.0 - math.exp(-math.tau * max(1.0, cutoffs[i]) / SAMPLE_RATE)
        state += alpha * (buffer[i] - state)
        out.append(state)
    return out


def high_pass(buffer, cutoff):
    """One pole high pass, as the difference between the signal and its own
    low passed self. Mostly used to take the mud out of a noise burst."""
    low = low_pass(buffer, cutoff)
    return [buffer[i] - low[i] for i in range(len(buffer))]


def band_pass(buffer, cutoff, q=4.0):
    """State variable filter, band output.

    THE ONE THAT GIVES A NOISE BURST A CHARACTER. Plain low passed noise is a
    "shh" whatever you do to its envelope; the same noise through a resonant
    band at 900 Hz is a stone hit, and at 3 kHz it is a blade. Resonance is the
    difference between a sound effect and a texture.

    Chamberlin's topology, which is stable while the coefficient stays below
    about 1 - hence the cutoff clamp, without which a sweep that runs up past a
    sixth of the sample rate blows the filter up into a wall of noise.
    """
    return _svf(buffer, cutoff, q, "band")


def res_low_pass(buffer, cutoff, q=4.0):
    return _svf(buffer, cutoff, q, "low")


def _svf(buffer, cutoff, q, mode):
    cutoffs = _as_series(cutoff, len(buffer))
    limit = SAMPLE_RATE / 6.0
    damping = 1.0 / max(0.5, q)
    low = 0.0
    band = 0.0
    out = []
    for i in range(len(buffer)):
        f = 2.0 * math.sin(math.pi * min(limit, max(1.0, cutoffs[i])) / SAMPLE_RATE)
        high = buffer[i] - low - damping * band
        band += f * high
        low += f * band
        out.append({"low": low, "band": band, "high": high}[mode])
    return out


# --- shaping ---------------------------------------------------------------

def drive(buffer, amount):
    """Soft saturation. Adds harmonics and, more usefully, glues a peak down
    without the hard clip's crunch."""
    return [math.tanh(sample * amount) / math.tanh(amount) for sample in buffer]


def bitcrush(buffer, bits=6, hold=1):
    """Quantise and hold. The cheap way to make something read as artificial -
    an energy weapon, a UI refusal - rather than as a physical object."""
    levels = float(2 ** bits)
    out = []
    held = 0.0
    for i in range(len(buffer)):
        if i % max(1, hold) == 0:
            held = math.floor(buffer[i] * levels) / levels
        out.append(held)
    return out


def delay(buffer, time, feedback=0.35, mix=0.35, taps=6):
    """Fixed delay line. Not a reverb - a handful of echoes, which is enough to
    put a sound in a space without a convolution and without the tail that
    would smear the next twenty shots together."""
    step = n_samples(time)
    out = list(buffer)
    out += [0.0] * (step * taps)
    for tap in range(1, taps + 1):
        level = mix * (feedback ** (tap - 1))
        if level < 0.001:
            break
        offset = step * tap
        for i in range(len(buffer)):
            out[i + offset] += buffer[i] * level
    return out


# --- assembly --------------------------------------------------------------

def mix(*buffers):
    """Sums buffers of any lengths, result as long as the longest."""
    longest = max(len(b) for b in buffers)
    out = [0.0] * longest
    for buffer in buffers:
        for i in range(len(buffer)):
            out[i] += buffer[i]
    return out


def concat(*buffers):
    out = []
    for buffer in buffers:
        out += buffer
    return out


def at(buffer, offset, length=None):
    """Places a buffer `offset` seconds in, so mix() can lay out a sequence."""
    out = silence(offset) + list(buffer)
    if length is not None:
        target = n_samples(length)
        out = out[:target] + [0.0] * max(0, target - len(out))
    return out


def gain(buffer, amount):
    return [sample * amount for sample in buffer]


def fade_out(buffer, duration=0.005):
    """THE LAST THING EVERY SOUND GETS. A buffer that ends on a non-zero sample
    ends with a step to silence, and that is a click on the tail of an otherwise
    clean effect - the exact artefact that makes generated audio sound broken."""
    count = min(len(buffer), n_samples(duration))
    out = list(buffer)
    for i in range(count):
        out[len(out) - count + i] *= 1.0 - (i / max(1, count - 1))
    return out


def normalize(buffer, peak=0.89):
    """Scales so the loudest sample sits at `peak`.

    A SHARED CEILING IS WHY THE SET SOUNDS LIKE A SET. Per-sound levels get
    balanced on the mixer and in the .tres; what this guarantees is that none of
    them arrives already clipped, and that raising one in the game does not
    require discovering it was 20 dB quieter than its neighbour first.

    Peak and not RMS deliberately: these are transients, and an RMS match makes
    a long explosion quiet and a short click deafening.
    """
    loudest = max((abs(sample) for sample in buffer), default=0.0)
    if loudest < 1e-9:
        return list(buffer)
    return gain(buffer, peak / loudest)


def finish(buffer, peak=0.89):
    """Normalise, de-click the tail, and trim the silence off the end."""
    trimmed = list(buffer)
    while len(trimmed) > 1 and abs(trimmed[-1]) < 1e-5:
        trimmed.pop()
    return fade_out(normalize(trimmed, peak))
