# The shipped blueprints were never in a build, and the reason was two calls, not one

Players who downloaded the build opened the Blueprints card and found nine empty squares. The
plans that ship with the game are read correctly in the editor, in every headless run and in
every test, and are read by nothing at all in an exported build.

The cause is the one `2026-09-07-content-warmer-never-ran-in-a-build.md` wrote up the day
before — an export leaves a `.remap` where a `.tres` was — reached through a different door,
plus a second failure of the same family that the earlier finding never touched: **a type hint
naming a script class stops resolving once the resource is binary.**

## What was asked

"Players downloaded my build and did not have the default blueprints. Check that — I am not
sure whether it was an outdated build or whether I got it wrong."

It was not an outdated build.

## How it was measured

Two ways, because the first cannot see the code and the second cannot see a real build.

**1. The shipped pack's own directory.** `Builds/Windows/LTW_Test.pck`, parsed the way the
earlier finding describes (a `uint64` directory offset at header offset 32, then a count and
per-entry path length, path, offset, size, MD5, flags). That build predates the feature, so it
proves the file layout and nothing about blueprints: no path in it ends in `.tres` at all.
Every text resource is present twice — as `<name>.tres.remap` in its own folder, and as
`.godot/exported/<hash>/export-<md5>-<name>.res`.

**2. Two throwaway Godot projects outside this repo**, exported to a pack with the same 4.7.2
binary and run with `--headless --main-pack`, so the same code could be run from source and
from a pack and the two answers compared. The second of them contains the **real**
`BlueprintLibrary.gd` and the **real** `Resources/Blueprints/*.tres`, with `TowerLayout` cut
down to its exports and `load_file` verbatim, and a three-line `Log` stub. That is what makes
this a measurement of this project's code rather than of a toy.

Neither touches the repo, so nothing had to be added to `[autoload]` while an editor was open.

## What was found

The bare probe, run from source and then from its own exported pack. Only three rows move:

| | source | exported pack |
| --- | --- | --- |
| `FileAccess.file_exists("res://Defaults/thing.tres")` | true | **false** |
| `FileAccess.file_exists("res://Defaults/thing.res")` | false | false |
| `ResourceLoader.exists(path)` | true | true |
| `ResourceLoader.exists(path, "Thing")` — script class | true | **false** |
| `ResourceLoader.exists(path, "Resource")` — engine class | true | true |
| `ResourceLoader.load(path, "")` | ok | ok |
| `ResourceLoader.load(path, "Thing")` — script class | ok | **null** |
| `ResourceLoader.load(path, "Resource")` — engine class | ok | ok |
| `load(path)` | ok | ok |

The load failure is not silent on stderr — `Resource file not found:
res://.godot/exported/<hash>/export-<md5>-thing.res (expected type: Thing)` — but it is silent
everywhere a player or a developer would look, and the caller only ever sees `null`.

The mechanism for the type-hint rows is the loader being chosen by extension-for-type.
`ResourceFormatLoaderText` answers `"tres"` for **any** type it is asked about, so a
script-class hint costs nothing while the file is still text. `ResourceFormatLoaderBinary` asks
`ClassDB`, which has never heard of a script class, so no loader recognises the path and the
load is refused outright. Exactly the asymmetry that makes something correct from source and
broken in a pack.

The faithful probe, running this project's own `BlueprintLibrary` over its own plans:

| | source | exported pack |
| --- | --- | --- |
| before the fix | every shipped slot, with its real tower count | **no slots at all** |
| after the fix | every shipped slot, with its real tower count | the same, unchanged |

The top-right cell is what players got. The two left-hand cells are the positive control: the
same code, the same files, one variable changed, and the editor answer never moves — which is
precisely why this shipped.

## Where the bugs were

Three existence checks and one type hint, in two files:

- `BlueprintLibrary._default_path` asked `FileAccess.file_exists` for both the `.tres` and the
  `.res` spelling. Both are false in a build, so it returned `""` and every slot read as empty
  before anything was ever loaded. The "two spellings" comment above it was honestly meant and
  wrong: a converted resource does **not** appear as a sibling `.res`.
- `BlueprintLibrary._read` asked `FileAccess.file_exists` again, so it would have refused even
  had the path survived.
- `TowerLayout.load_file` asked `FileAccess.file_exists` a third time — and then passed
  `"TowerLayout"` as the type hint, which would have refused the load on its own.

Four gates, all shut, for one feature. Fixing any three of them changes nothing, which is worth
knowing before believing a partial fix.

`is_shipped_default` keeps `FileAccess`, correctly: it asks about a `user://` file, which is a
real file with no remap, and the question there really is "did this player write one".

A player's own saved blueprints were never affected, and that is worth stating because it
narrows what to re-test: a `user://` file is text, is not remapped, and the text loader accepts
a script-class hint. Only the shipped defaults ever crossed the seam.

## What was changed

Every one of those checks becomes `ResourceLoader.exists(path)` with **no type hint**, and the
load drops its hint. The `as TowerLayout` cast that follows is what checks the type, and always
was — the hint was never buying anything the cast did not already.

An audit of every `ResourceLoader.load`/`.exists`/`load_threaded_request` call under `Scripts/`
found the only other type hints to be `"PackedScene"`, in `ContentWarmer` and `MatchLoading`.
That is an engine class and is safe, as the table above shows.

## Why it was silent

The same three conditions as the warmer, one day earlier:

1. **The editor cannot see it.** From source the files really are `.tres` and the script class
   really is loadable, so every run a developer makes is correct.
2. **An empty slot is a legitimate state.** Not every square ships with a plan in it, so a card
   of empty squares does not read as a fault. `charge_count` returning `-1` draws no number,
   exactly as intended for a slot nobody has saved into.
3. **Nothing logs.** `_read` is deliberately quiet so unused slots do not print a line each per
   boot — and the one gate that would have said something, `load_file`'s warning, was never
   reached, because `_default_path` had already returned `""`.

## Traps

Both engine traps here are general rather than about blueprints, so they are written into
`../../CLAUDE.md` rather than left in this file. In short: **in a build there is no `.tres`, so
ask `ResourceLoader`, never `FileAccess` — and never hand `ResourceLoader` a type hint naming a
script class.**

The two worth keeping here are about the shape of the investigation rather than the engine.

**A feature can be broken by four independent gates, and fixing one proves nothing.** The
instinct after finding `_default_path` was to fix it and stop; the diagnosis was complete and
the symptom was explained. What actually mattered was running the whole real class end to end
in a real pack, which is the only thing that could have caught the type hint two calls further
down — a different file, a different mechanism, and enough on its own to keep the feature
broken while the write-up looked finished.

**Reproducing an export outside the repo is cheap, and it is the only thing that makes "only in
a build" a measurement.** Two small projects, exported with `--export-pack` and run with
`--main-pack`, need no autoload, no editor restart and nothing to delete afterwards, and they
can run the same code twice with one variable changed. Worth doing the moment those words
appear.

## What is still open

- **Nothing checks this at boot.** A build that reintroduces the bug shows empty squares and
  logs nothing, exactly as before. A check comparing what the shipped folder holds against what
  `BlueprintLibrary` reads would have to run inside a build to be worth anything, and where its
  complaint should go — the load screen, the card itself — is not decided.
- **The fix is proven against a probe pack, not against a client build a player ran.** The
  confirmation is one look at the Blueprints card in the next build.
- Whether the shipped plans are the right ones is a separate question and untouched here.
