# The content warmer never ran in a build, and said so where nobody looked

`ContentWarmer` was written on 2026-09-06 to end the ~1 s freezes of playtest 1 by loading every
spawnable asset on the load screen. In playtest 2, one day later, every client in every match
logged:

    match.warmed  { "stats": 0, "scenes": 0, "other": 0, "held": 0, "ms": 0.0 }

It walked nothing, held nothing and finished in zero milliseconds, on all four machines, in every
match. **The fix for playtest 1's freezes has never once run in an exported build.**

## What was asked

Nothing - this was found while looking for the cause of playtest 2's lag, which turned out to be
unrelated (`2026-09-07-playtest-2-delay-cliff.md`).

## How it was measured

The `match.warmed` line above, from the four session journals. Then the client's own
`godot.log`, which carries the warning the class already emits for exactly this case:

    WARNING: ContentWarmer found nothing to warm [ res://Resources/UnitStats, res://Resources/Config ]

No `ContentWarmer was given a folder that does not resolve` line accompanies it, so the folders
opened fine and the walk simply matched no files.

Then, decisively, the shipped pack: `Builds/Windows/LTW_Test.pck` from the playtest build, with
its directory parsed directly. Godot 4.7's PCK puts a `dir_offset` as a `uint64` at header offset
32; the directory there is a `uint32` count followed by, per entry, a `uint32` path length, the
path with no `res://` prefix, then offset, size, MD5 and flags.

## What was found

Under `Resources/UnitStats/` the pack holds **196 entries, every one of them ending in
`.tres.remap`, and not one ending in `.tres`.** Across the whole pack: 1,059 `.tres.remap`
entries and zero `.tres`.

`_tres_files` matched `entry.ends_with(".tres")`. In the editor that is every stats file; in a
build it is nothing at all.

The cause is the export converting text resources to binary: `foo.tres` is replaced by a
`foo.tres.remap` stub, and the binary itself is filed away under
`.godot/exported/<hash>/export-<md5>-foo.res` rather than beside the original. So neither the
original spelling nor a sibling `.res` appears where the walk was looking.

Running the old and new predicates over the real pack file list:

| folder | entries | old predicate | new predicate |
| --- | --- | --- | --- |
| `Resources/UnitStats/` | 196 | 0 | 196 |
| `Resources/Config/` | 16 | 0 | 16 |

212 files, which is exactly the `stats` count an editor run reports.

## Why it was silent

Three things had to line up, and they did:

1. **The editor cannot see it.** In the source tree the files really are `.tres`, so every
   headless run, every editor run and every test warms correctly. Only an exported build is
   affected, and only the build was ever taken to a playtest.
2. **The warning went to the wrong audience.** `Log.warn("ContentWarmer found nothing to warm")`
   fired on every client, correctly, on the first frame of every match - into `godot.log`, which
   is read after a playtest goes wrong rather than during one. `SessionLog`, which is the file
   anybody actually opens, recorded the zeroes as a successful warm.
3. **A no-op warmer looks like a fast warmer.** The load screen filled instantly and the match
   started. The only visible symptom is the freezes it was supposed to remove still happening,
   which is indistinguishable from the fix not working.

## What was changed

`ContentWarmer._tres_files` now trims `.remap` before testing the extension, and appends the
trimmed path:

    elif full.trim_suffix(".remap").ends_with(".tres"):
        out.append(full.trim_suffix(".remap"))

`res://.../foo.tres` is what gets loaded in both cases; `ResourceLoader` resolves the remap
itself, and every other consumer of these paths names them that way too.

A bare `.res` is deliberately still ignored. Every converted file leaves a remap behind, so
accepting both spellings would find each resource twice in a build and once in the editor - and
in this Godot version the `.res` is not in the folder anyway.

## Trap

**The three registries already knew.** `AbilityRegistry._scan_file`, `UnitTypeRegistry` and
`TechRegistry` all trim `.remap` before checking the extension, and `AbilityRegistry` carries a
docstring saying why: *"the name on disk is not the name in the source tree ... Both spellings
have to be accepted or the registry is right in the editor and short in the build, which is the
worst way round."*

So this was a solved problem with the answer written down three times, and a new folder walk
written a fortnight later walked straight into it. The lesson is not about remaps:

**When you write the fourth copy of a loop somebody has already written three times, read one of
them first.** A fresh `DirAccess` walk is short enough to feel like it needs no research, which
is exactly what makes it the shape that repeats an old bug.

The narrower rule, worth keeping next to the code: **anything that enumerates resource files by
extension must handle `.remap`, or it is correct in the editor and empty in the build.**

## What is still open

- **Nothing proves this end to end yet.** The predicate was verified against the real filenames
  in the shipped pack, which is a strong check but not the same as watching a build warm. The
  confirmation is one line in the next build's journal: `match.warmed` should report roughly 212
  stats and several hundred scenes instead of zeroes.
- **`begin`'s warning should be louder than a warning.** A warmer that finds nothing is not a
  degraded warm, it is no warm, and the load screen is the one moment where stopping to say so
  costs nothing. It currently continues silently into the match.
- Whether playtest 1's freezes actually go away once it runs. That was never tested, because it
  has never run.
