# SfxGen

Synthesises the placeholder sound effects: tower fire, impacts, creep death,
and the match feedback sounds. Output lands in `Audio/Generated/<Category>/`.

Not part of the build. Nothing at runtime knows it exists, and `.gdignore`
keeps Godot's filesystem out of this folder entirely.

## Running it

From the **project root**, not from here:

```
python Tools/SfxGen/generate.py                     writes every sound
python Tools/SfxGen/generate.py --check             reports, writes nothing
python Tools/SfxGen/generate.py --only creep_death  just that one
python Tools/SfxGen/generate.py --preview OUT.wav   plus a review reel
```

Needs Python 3 and nothing else - no Godot, no packages, same as ModelGen and
IconGen.

It is idempotent: a run with nothing changed rewrites every file byte for byte,
so `git status` after a run tells you exactly what your edit did. That property
is load-bearing rather than tidy, and it is why every noise source is seeded
from its own sound's NAME via `crc32` - never from the global `random` module,
and never from `hash()`, which Python randomises per process.

`--preview` writes every sound end to end with a gap between them, which is the
only practical way to judge whether the set hangs together. Give it a path
outside the project; the reel is for listening to, not for shipping.

Godot imports the WAVs on its next filesystem scan and writes the `.import`
files itself. This tool does not, because a `.import` carries a uid and
CLAUDE.md is clear that we never invent one.

## Why it exists

The roster is ten element lines plus a creep list, which is north of a hundred
sounds. Sourcing them one at a time gives a hundred unrelated noises; generating
them gives a **language** - the line picks the timbre, the tier raises the pitch
and lengthens the tail - with one file to change when a line turns out to be
wrong. That is the argument ModelGen makes for the models, and `sounds.py` is
its `style.py`.

## The files

| File | What is in it |
| --- | --- |
| `generate.py` | The CLI, the roster walk, the seeding. Start here. |
| `sounds.py` | **The sound language.** One function per sound, plus `TIER`. This is the file you edit. |
| `dsp.py` | Oscillators, envelopes, filters, shaping. No sound of its own. |
| `wav.py` | Mono 16 bit PCM out. |

## Rules a new sound has to meet

These were authored by Claude rather than handed down, and exist for the same
reason `PLACEHOLDER_ART.md`'s rules do: continuity across a roster nobody can
hold in their head at once. Break one when it is wrong - in `sounds.py`, so the
whole set moves together.

- **Mono.** Anything in the world plays through an `AudioStreamPlayer3D`, and a
  stereo stream cannot be panned by one. `wav.py` enforces this.
- **Short.** Fire sounds under 0.2 s, impacts under 0.3 s. A shot fires twenty
  times a second in a full maze, and anything that outlasts its own rate of fire
  becomes a drone the moment the maze fills. `explosion` is the deliberate
  exception and is rare by design.
- **End on `dsp.finish()`.** It normalises to a shared peak ceiling, trims the
  dead tail and fades the last few milliseconds. Skipping it gives a click on
  the tail, which is the single artefact that makes generated audio sound broken
  rather than merely cheap.
- **Never touch `random` directly.** Take the `rng` you were handed. See the
  idempotency note above.
- **Peak normalised, never RMS.** These are transients; an RMS match makes a
  long explosion quiet and a short click deafening.

## Traps already paid for

- **A buffer that starts at full amplitude starts with a click.** `env_decay`
  takes a 3 ms attack for exactly this and it is not optional, even though it is
  inaudible as an attack.
- **The state variable filter blows up above about a sixth of the sample rate.**
  A cutoff sweep that runs up past it turns into a wall of noise rather than
  erroring. `_svf` clamps; do not remove the clamp.
- **Godot's WAV importer defaults to QOA**, which is lossy and costs a decode
  per voice. `project.godot`'s `[importer_defaults]` pins `compress/mode` to 0
  (PCM) project-wide, which is the whole reason this tool writes PCM. If a WAV
  ever shows up as mode 2, that section was lost in an editor save.
- **`hash()` is randomised per process** unless `PYTHONHASHSEED` is set, so
  seeding from it would break idempotency in a way that only shows up as
  mysterious churn in `git status`. `crc32` is stable.

## What is not here

Music, ambience and UI. Music and ambience want length and movement, which is
where synthesis stops being convincing and a real recording starts being worth
its file size. UI is where a real sample is worth the most and where there are
fewest of them, so those three live hand-made in `Audio/Placeholder/`.
