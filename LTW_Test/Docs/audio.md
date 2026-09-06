# Audio

What the audio build is and where each part of it lives. Architecture, not
controls and not numbers — every level, cap and gap is authored in
`Resources/Config/audio_config.tres` and is the authority on itself.

Nothing here decides a gameplay outcome. Audio is presentation in the sense
`multiplayer.md` means it: a dedicated server never wires any of it, runs the
same match without it, and cannot be desynced by it. That is a hard line rather
than a tidy one — `AudioHub` uses wall-clock milliseconds and the local camera
to decide what to play, and both differ between two machines running the same
match, which is exactly why no simulation may read them.

---

## 1. The mixer

Six buses — Master, UI, SFX, Music, Speech, Atmo — in
`Resources/Config/default_bus_layout.tres`, named by `project.godot`'s
`audio/buses/default_bus_layout`.

**The settings half already existed.** `UserSettings` owns the channel list, the
per-channel levels and the mute flag, persists them to `user://settings.cfg`,
and the options screen drives them. What audio added was the other end:
`UserSettings.apply_volumes()`, called from `Boot._dispatch()` beside
`apply_window_mode()` and again on every change.

**Buses are resolved BY NAME, never by index.** `UserSettings.AUDIO_BUS_NAMES`
holds the names and `AudioServer.get_bus_index()` does the lookup. The enum's
numbers happen to match the layout's order today and relying on that is the
trap: reordering the buses in the editor would silently aim every slider at the
wrong one. A name that resolves to nothing is a `Log.err`, because the quiet
version of that failure is a slider that moves nothing and never says why.

Three parallel arrays describe a channel — the settings-file key, the on-screen
label, and the bus name — and they stay separate on purpose. They answer to
three different owners: a saved file that may never change, a wording that may
change whenever it is wrong, and the bus layout.

Mute is the Master bus's own flag, not a volume of zero. Zeroing would work and
would then have thrown the player's levels away, since unmuting has to put them
back and the only copy is the one being overwritten.

## 2. AudioHub

`Scripts/Audio/AudioHub.gd`. The one thing in the project that plays a sound.

An autoload, because music has to survive a scene change and a node inside a
match scene cannot. Everything reaches it through statics, so no caller holds a
reference and `References` does not carry one.

**Every static is safe to call when the autoload is absent.** A `class_name` is
a global identifier and a static resolves without an instance, so a call from a
headless probe, a bare `--script` run, or a build where the `[autoload]` line
has not landed is a no-op rather than a crash. Presentation must never be able
to stop a simulation.

It owns three things and nothing else: the pooled players, the stream cache and
the voice budget. How loud one tower's shot is belongs on that tower's stats;
the mixing rules belong on `AudioConfig`.

## 3. The voice budget

**The setting that decides whether a loaded match is playable.** Every tower in
every lane fires on the same tick, so requests per second run into the thousands
and the only question is how many are allowed through. Three gates, cheapest
first:

- **Distance.** A sound further from the camera than the configured range is
  skipped before a voice is spent on it.
- **The same-sound gap.** Forty towers of one type firing on one tick is forty
  requests for one file inside a millisecond. Playing all forty does not sound
  like forty shots — they are phase-identical and sum, so it sounds like one
  shot forty times as loud. One gets through and the rest are dropped.
- **Nearest to the camera wins.** With every voice busy, a new sound takes one
  only if it is closer than the furthest thing currently playing.

That last gate **is** the lane-audibility rule. With many lanes running, the
voices end up spent on the lane being looked at without anything having to know
what a lane is. A sound that is off screen is additionally attenuated, decided
by camera projection maths — never a physics query, per the hard rule in
`CLAUDE.md`.

None of this has been measured under a full maze. The authored caps are starting
guesses, and `Scenes/Tools/perf_bench.tscn` is where they should be checked.

## 4. Buttons

Automatic. `ButtonSoundBinder` is `AudioHub`'s own child, connects to
`SceneTree.node_added`, and gives every `BaseButton` its click, hover and
refusal without one of them being authored. Runtime-instanced UI scenes arrive
on the same path, so a scene change needs no rescan.

This is inverted from the version it was rewritten from, where the node on the
button was what made it audible. Every interactive thing in the game already
extends `Button`, so opt-out costs nothing to author and cannot be forgotten,
while opt-in means one hand edit per button and a silent failure on the one that
gets missed.

`ButtonSounds` is now the override marker: drop it on a button to silence it or
to name different sounds. A plain `Node`, so it has no layout and cannot disturb
what it sits under.

**The disabled-click sound needs no trickery.** A disabled `Button` emits no
`pressed`, which is why the original carried an invisible second Button to catch
the click. It does still emit `gui_input` — `Control` emits that signal before
`BaseButton`'s own disabled early return, and `disabled` never changes
`mouse_filter`. One connection replaces the catcher and the two methods that had
to be called by hand whenever a button's disabled state changed, because nothing
signals that.

`node_added` fires for every node in the game, creeps included. The callback is
one cast and an early return, and it stays acceptable only while it stays that
shape — nothing that walks the tree or reads `References` belongs in it.

## 5. Where a sound is named

**On the thing it describes.** A tower's fire sound belongs on its `AttackStats`
and a creep's death sound on its `CreepStats`, for the same reason a tower's
gold cost lives on its `BuildingStats`. `AudioConfig` holds only what belongs to
nobody: the interface, and the match-wide events.

**By path, never as a stream.** An `AudioStream` held as an `ext_resource` is a
hard load-time dependency, so loading a config or a stats resource would pull
every sound it names into memory whether or not one is ever played. Same rule
and same reasoning as a `.tres` naming a scene. `AudioHub` owns one cache for
the whole game, keyed by path — which is what lets the Phase 2 per-unit sounds
share it rather than growing a cache each.

**The streams are warmed on the load screen**, so nothing loads one mid-match.
`ContentWarmer` reflects over the unit stats folder and over
`ContentConfig.shared_config_folder` — which is where `audio_config.tres` lives
— collecting any String property that names a `.wav`, `.ogg` or `.mp3`, and
holds them for the life of the process. `ResourceLoader` then hands `AudioHub`
the cached resource, so the lazy loads cost nothing from the first frame.
Nothing calls into audio to make that happen and nothing should.

Two silent couplings follow from that, neither of which errors:

- **Move `audio_config.tres` out of that folder and its sounds stop being
  warmed.** The symptom is a hitch on the first click, not a message.
- A sound named anywhere other than a resource in those folders is not warmed
  either. `AudioHub.warm()` exists for that case and is currently called by
  nothing.

`References.audio_config` is **wired per scene**, like every other `References`
entry, and a missing wire fails silently — the getter returns null and the
sounds simply never play.

## 6. Placeholder audio

`Tools/SfxGen` synthesises the in-world sounds: stdlib Python, run from the
project root, output checked in and overwritten. `Tools/SfxGen/README.md` is the
procedure and `sounds.py` is the sound language.

The argument for generating rather than sourcing is the one `PLACEHOLDER_ART.md`
makes for the models: a roster this size sourced one file at a time gives
unrelated noises, while generating gives a language — the line picks the timbre,
the tier raises the pitch and lengthens the tail — with one file to change when
a line turns out wrong.

UI sounds are hand-made and live in `Audio/Placeholder/`. That is where a real
recording is worth most and where there are fewest of them.

## 7. The one step still outstanding

`AudioHub` is written, tested and committed, but **it is not yet an autoload**,
so at runtime `AudioHub.instance` is null and every call no-ops. Nothing breaks
— the project boots clean and silent — but no sound plays until this lands.

Add to `project.godot`, in the existing `[autoload]` section:

```
AudioHub="*res://Scripts/Audio/AudioHub.gd"
```

**Godot's editor must be closed when this is written.** The editor holds its own
copy of ProjectSettings, does not re-read the file, and a filesystem scan does
not help — an autoload added from outside reads as "Identifier not found" until
the editor is restarted. Headless runs are unaffected, which is what makes it
confusing. See `CLAUDE.md`.

To confirm it took, boot and press a button in the main menu: it should click.
`AudioHub.is_available()` returns true once the instance exists.

## 8. Not built yet

- **Nothing in the world makes a sound.** Towers, creeps and impacts have no
  sound wired; the paths on `AttackStats` and `CreepStats` do not exist yet.
  The match-event sounds are authored in the config but nothing emits them.
- **Music and ambience.** `AudioHub.play_music()` works and nothing calls it.
  `AudioClipSet` and `IntervalClipSet` are authored and unused.
- **The voice budget is unmeasured**, as above.
- **`AudioListener3D`** is not placed; world sounds currently use the camera as
  the listener by default.
