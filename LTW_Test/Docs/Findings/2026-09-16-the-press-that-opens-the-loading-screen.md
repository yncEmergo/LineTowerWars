# The press that opens the loading screen

**2026-09-16. Windows dev PC, Godot 4.7.2, run from source.**

> **Rewritten the same day.** The first version of this finding concluded that the reported
> hold did not reproduce. It did reproduce, on the first press, every time - the probe was
> pressing the wrong buttons. How that happened is in "How the wrong answer was reached" at
> the bottom, because it is worth more than the number.

## What was asked

Pressing a button that starts a match was reported to hold for 1-2 seconds before the
loading screen appeared. The ask was not to remove the loading, which is expected to take a
moment, but to get the loading screen up FIRST, so the button answers immediately and the
wait happens with something on screen that explains it.

## How it was measured

A throwaway `Scripts/Dev/StartLagProbe.gd`, loaded as an autoload through an `override.cfg`
deleted afterwards, and armed only by `-- --startlag <tutorial|skirmish|test>`:

    godot --path . -- --startlag test

It presses the real buttons by matching their text and emitting `pressed`, then reports every
frame longer than 25 ms, the frame each press lands on and the eleven after it, and - the
number that matters - press to GLASS: the moment `SceneTree.current_scene` changes, and the
moment `RenderingServer.frame_post_draw` first fires with it up. Measured on the renderer
rather than inferred from a log line in `_ready`.

## What was found

**The main menu's three start buttons do not do the same thing, and only one of them was
slow.** Press to the next screen being drawn:

| Button | Route | Press to glass |
| --- | --- | --- |
| Tutorial | loading screen | 15.6 ms |
| Start Match (skirmish setup) | loading screen | 16.6 ms |
| **Test Scene** | **straight to the game scene** | **1009 ms** |

The Test Scene press landed on a single frame of **990.1 ms**, with the main menu still on
screen and no loading screen anywhere in the path. `MainMenu._on_play_pressed` called
`MenuNavigation.to_game` directly, and `change_scene_to_file` loads the scene
SYNCHRONOUSLY, inside the press - so the press was loading the entire 3D game on the main
thread before a pixel of it could exist.

That is the whole of the reported hold, and it is why the tutorial felt fine: the tutorial
was already going the other way.

Measured alongside, on the same runs: the synchronous cost of the MENU scenes, which is the
same mechanism at a hundredth of the size - `match_loading.tscn` 25.6 ms cold in-process,
`skirmish_setup.tscn` 29.8 ms, `main_menu.tscn` 38.2 ms. Real, but not what was reported.

## What was changed

**`MainMenu._on_play_pressed` now goes through the loading screen**, the same road the
tutorial takes, building the stand-in roster with `MatchSetup.from_config` - the same call
`Main._take_setup` would have made if it had been handed nothing. Paired, same commit, one
line flipped in place, same machine, same probe:

| | Before | After |
| --- | --- | --- |
| Worst frame on the press | 990.1 ms | 12.1 ms |
| Press to a screen drawn | 1009 ms (the game) | 14.3 ms (the loading screen) |
| Press to the game drawn | 1009 ms | 1638 ms |

**The total got longer on purpose.** The test scene now pays for the content warm-up it
never had, which is the point of the screen it now goes through. It shows in the same two
runs: in the 20 s after the world was up, the old route hitched seven more times, twice over
80 ms, as each kind of content was spawned for the first time; the new route hitched none.
That is `ContentWarmer` doing what `Findings/2026-09-06-playtest-1-freezes.md` built it for,
in a scene that had been quietly opted out of it.

**Second, smaller, and found before the real cause:** `SceneUtil` gained `prewarm(path)`, a
background `load_threaded_request` held in a static dictionary for the life of the process.
`change_scene` collects a prewarmed scene and uses `change_scene_to_packed`, falling back to
`change_scene_to_file` for anything nobody asked for ahead of time. `Boot` asks for every
menu screen except the one it is about to open, from `MenuConfig.menu_scene_paths()` - which
deliberately excludes the game scene, that being what the loading screen exists to load with
a bar on screen. It took the Single Player press from 53.2 ms to 21.3 ms. Kept on its own
merits: it is the same trap one order of magnitude down, on every remaining menu button.

## How the wrong answer was reached

The report said "the button that starts a game / opens the loadscreen". There are four such
buttons and I wrote the probe to press two of them - the two that go through the loading
screen, because the loading screen was what the report was about. Both measured 16 ms, and
16 ms twice reads as a clean bill of health rather than as two samples of the same route.

**The probe pressed what the question was assumed to mean.** Every button named in the
report should have been pressed, precisely because the interesting possibility was that they
do not all do the same thing - and here, one of the four did not. It is CLAUDE.md's rule
about a test topology that cannot falsify its assumption, reached through the harness:
sampling only the paths that share an implementation cannot discover that a fourth path has
a different one.

The cheap check that would have caught it: **the route each button takes was readable in one
grep of `MenuNavigation` callers** and was never looked at, because the measurement felt more
authoritative than the map.

## What is still open

- **Single player was not measured end to end**, being still in development. It uses the
  same route as the tutorial and the same `_on_start_pressed` already measured at 16 ms, so
  it is expected to be fine, but that is inference.
- **Nothing here was measured on an exported build or a cold cache**, which is where
  `ContentWarmer` recorded a tester at a hundred times this machine's per-asset cost. The
  prewarm was written for that case and is unproven in it.

## Traps

The general one - that `change_scene_to_file` loads synchronously inside the press, so a
loading screen cannot report its own loading - is in `../../CLAUDE.md` rather than here.
