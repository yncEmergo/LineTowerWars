"""Regenerates the placeholder sound effects.

    python Tools/SfxGen/generate.py                    writes every sound
    python Tools/SfxGen/generate.py --check            reports, writes nothing
    python Tools/SfxGen/generate.py --only NAME        just that one
    python Tools/SfxGen/generate.py --preview OUT.wav  plus a review reel

RUN IT FROM THE PROJECT ROOT. The output path below is relative to it.

WHY THIS EXISTS. The roster is ten element lines and a creep list, which is
somewhere north of a hundred sounds nobody is going to record twice. Sourcing
them one at a time gives a hundred unrelated noises; generating them gives a
LANGUAGE - line picks the timbre, tier raises the pitch and lengthens the tail -
with one file to change when a line's character turns out to be wrong. That is
the same argument ModelGen makes for the models, and sounds.py is its style.py.

**The output is checked in and is ordinary PCM .wav.** Nothing at runtime knows
this tool exists. Replace one with a real recording whenever that is better -
just know the next run overwrites it, so drop a recording in Audio/Placeholder/
instead and point the .tres there.

It writes into:
    Audio/Generated/<Category>/<name>.wav

Godot imports them on its next filesystem scan and writes the .import files
itself. This tool does not, because a .import carries a uid and CLAUDE.md is
clear that we never invent one.

IT IS IDEMPOTENT, and that is load-bearing rather than tidy. Every noise source
is seeded from the sound's own NAME via crc32 - never from the global random
module, whose seed changes per process, and never from hash(), which Python
randomises per process unless PYTHONHASHSEED says otherwise. So a run with
nothing changed rewrites every file byte for byte, and `git status` afterwards
tells you exactly what your edit did and nothing else.

Needs Python 3 and nothing else - no Godot, no packages, same as ModelGen.
"""

import os
import random
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import sounds
import wav

OUT_DIR = os.path.join("Audio", "Generated")

# Gap between sounds on the review reel. Long enough to tell where one ended.
PREVIEW_GAP = 0.4


def _rng_for(name):
    """This sound's dice, seeded from its name and nothing else."""
    return random.Random(zlib.crc32(name.encode("utf-8")))


def _render(name, build):
    return build(_rng_for(name))


def _duration(samples):
    return len(samples) / float(wav.SAMPLE_RATE)


def _selected(only):
    if only is None:
        return list(sounds.ROSTER)
    picked = [entry for entry in sounds.ROSTER if entry[1] == only]
    if not picked:
        known = ", ".join(entry[1] for entry in sounds.ROSTER)
        raise SystemExit("no sound named %r. Known: %s" % (only, known))
    return picked


def main(argv):
    check = "--check" in argv
    only = None
    preview_path = None

    if "--only" in argv:
        only = argv[argv.index("--only") + 1]
    if "--preview" in argv:
        preview_path = argv[argv.index("--preview") + 1]

    if not os.path.isdir("Audio"):
        raise SystemExit("run this from the project root - no Audio/ folder here")

    roster = _selected(only)
    written = 0
    changed = 0
    reel = []

    for category, name, build in roster:
        samples = _render(name, build)
        payload = wav.encode(samples)

        folder = os.path.join(OUT_DIR, category)
        path = os.path.join(folder, name + ".wav")

        existing = None
        if os.path.exists(path):
            with open(path, "rb") as handle:
                existing = handle.read()

        state = "same"
        if existing is None:
            state = "NEW"
        elif existing != payload:
            state = "CHANGED"

        if state != "same":
            changed += 1

        if not check:
            os.makedirs(folder, exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(payload)
            written += 1

        print("  %-8s %-14s %-16s %5.0f ms  %6.1f kB"
              % (state, category, name, _duration(samples) * 1000.0,
                 len(payload) / 1024.0))

        if preview_path:
            import dsp
            reel.append(samples)
            reel.append(dsp.silence(PREVIEW_GAP))

    if preview_path:
        import dsp
        wav.write(preview_path, dsp.concat(*reel))
        print("\nreview reel -> %s" % preview_path)

    if check:
        print("\n--check: %d of %d would change, nothing written"
              % (changed, len(roster)))
    else:
        print("\nwrote %d sound%s into %s (%d changed)"
              % (written, "" if written == 1 else "s", OUT_DIR, changed))
        print("Godot writes the .import files on its next filesystem scan.")


if __name__ == "__main__":
    main(sys.argv[1:])
