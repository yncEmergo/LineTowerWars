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
the mixing rules belong on `AudioConfig`; which sound a match event makes
belongs to `MatchAudio`.

**The autoload is called `Audio`, not `AudioHub`.** An autoload name and a
`class_name` share one namespace in Godot, so naming it after its class would
collide with the class every caller uses. The handle is never typed anyway -
everything reaches the hub through statics on `AudioHub` - and it matches what
the rest of the project already does: `Net`, `Commands`, `Replication` and
`Lockstep` are all short handles on classes named something longer.

### 2.1 The three ways to play a sound

**This is the one decision a caller makes, and it is the difference between a
sound that works and one that is silent at the moment it mattered.**

| | Where | Bus | Budgeted | For |
| --- | --- | --- | --- | --- |
| `play_at()` | a point in the world | SFX | yes | a tower firing, a shell landing, a creep dying |
| `play_event()` | nowhere | SFX | no | a life lost, income arriving, a build refused |
| `play_ui()` | nowhere | UI | no | a click, a hover, a press on a dead button |

**DIEGETIC (`play_at`)** is heard from where the camera is standing. It is
attenuated, culled by distance and pays the voice budget, because it is the
only one of the three a full maze can ask for a thousand times a second.

**EXTRADIEGETIC (`play_event`)** is about the MATCH rather than about a place
in it. It is deliberately not positional, and that is the whole point: these
are the sounds a player is meant to hear *while looking somewhere else*, which
is most of the time in a game with twelve lanes. Attenuating a leak by how far
the camera happens to be from the end zone would silence it in exactly the case
it exists for - the lane nobody was watching.

**THE INTERFACE (`play_ui`)** is the same flat shape on a different bus, so a
player who wants the clicks quieter has a slider that does not also turn the
game down.

The line between the last two is easy to get wrong and worth stating: `play_ui`
is about a CONTROL the player operated, `play_event` about something that
happened in the match. A build refused for want of gold is an event - it
arrives seconds after the press, with the player already doing something else.
A press on a greyed-out button is interface.

Getting it wrong is silent both ways round, which is why every entry on
`AudioConfig` says which it is in its own docstring.

### 2.2 MatchAudio

`Scripts/Audio/MatchAudio.gd`, the hub's own child, alongside
`ButtonSoundBinder` and for the same reason - audio is wanted wherever the hub
is and a second `[autoload]` line breaks a running editor.

**It is the score and the hub is the mixer.** It answers which sound a leak
makes, whether a refused build is the local player's business, and which of the
three calls above each event wants. Gameplay code calls one named line -
`MatchAudio.tower_placed(at)` - and never reaches for `AudioConfig` itself.

**It is both a node and a set of statics, deliberately.** A leak already has a
channel: `ReplicationService.leak_reported`, on an autoload that outlives a
match scene. Listening to it is strictly better than a call, because it fires
on the same terms wherever the leak was noticed and cannot be forgotten by the
next caller. Nothing emits "a tower landed", and adding a signal for audio
alone would be a channel with one subscriber - so those are calls. The node
half listens where there is something to listen to; the static half is called
where there is not.

**A sound named on a stats resource is NOT its business.** A tower's fire sound
is played by `AttackComponent`, straight out of the `AttackStats` it is already
holding, and an impact by the `AttackDelivery` that owns the path. `MatchAudio`
is only for what belongs to nobody.

**Two of its calls are on a per-unit path** - a creep spawning and a creep
dying - and both ask `AudioHub.is_available()` before they reach for anything
else, so a dedicated server pays one static bool per creep rather than a
`References` lookup.

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

Four fields carry it, and the split between the first two is the one worth
remembering:

- `AttackStats.fire_sound_path` - the RELEASE, played at the muzzle. A property
  of the weapon.
- `AttackDelivery.impact_sound_path` - the ARRIVAL, played where the hit lands.
  A property of how the shot got there and what it hit. A mortar and a crossbow
  share neither.
- `CreepStats.death_sound_path` and `spawn_sound_path` - per creep, and empty
  for the whole roster today.

**An empty path is an answer, not a fault**, on both of the attack fields, in
exactly the way `impact_scene_path` already works: a spinning blade that grinds
whatever stands next to it has no launch to announce, and the whole cutter line
is authored silent on the way out for that reason.

**The two creep fields have a roster-wide default behind them**, on
`AudioConfig.creep_death_path` and `creep_spawn_path`, which a creep naming
nothing falls back to. That is the one place the config names something a stats
resource could own, and it is a DEFAULT rather than a list: one entry, not two
hundred, and consulted only when the creep is silent about it. Every creep
should be audible when it dies - it is the feedback that says the maze is
working - so silence there is not something the roster wants to author.

The impacts deliberately have no such default: a default would take the silence
away from the things that mean it.

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

The reflection is why the four new fields needed nothing doing to them:
`ContentWarmer._asset_paths_on` walks NESTED resources, so an
`impact_sound_path` on an `AttackDelivery` hanging off an `AttackStats` hanging
off a tower's `BuildingStats` is collected without anything at the top level
mentioning it.

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

**WHICH tower gets which sound is ModelGen's, not SfxGen's.**
`Tools/ModelGen/audio.py` holds the whole mapping - branch to release, branch to
impact, element to both, and a short list of the shapes that disagree with their
own line - and `tower_content.py` and `element_content.py` write it into every
generated `.tres`. The two tools are deliberately apart: SfxGen renders `.wav`
files and has never heard of a roster, and that file knows the roster and
renders nothing.

So **a hand edit to a `fire_sound_path` in a generated `.tres` is overwritten by
the next ModelGen run.** Change `audio.py` and re-run, the same rule every other
generated value follows.

The mapping reads richer than the set actually is, and `audio.py` says so at the
top: there is ONE arcane release sound, so nine of the ten element lines share
it and are told apart by their projectile and their impact rather than by what
leaving the tower sounds like. SfxGen also carries a TIER table that no tower
uses yet. Both are gaps in the rendered set rather than in the mapping, and the
fix for both is more sounds in `sounds.py`.

## 7. What is wired

Everything generated has a home. The events below are live and were each proven
firing in a real client match:

| Sound | Kind | Fires from |
| --- | --- | --- |
| click, hover, refused | interface | `ButtonSoundBinder`, automatically |
| tower fire | world | `AttackComponent._fire`, at the muzzle |
| impact | world | `AttackDelivery.spawn_impact`, where the hit lands |
| creep spawn | world | `Creep.spawn` - a fresh send only, never a recycle |
| creep death | world | `Creep._die`, after the death passives have had their turn |
| tower placed | world | `Builder._start_pending_build`, at the tower |
| build refused | flat | `Builder`, on each of the four ways an order comes to nothing |
| life lost | flat | `MatchAudio`, on `Replication.leak_reported` |
| income paid | flat | `PlayerManager._pay_all` |

Two of those are worth knowing the reasoning behind, because both look like
mistakes until the reason is stated.

**A tower being placed is a WORLD sound and is not filtered to the local
player.** Under lockstep every client simulates every lane, so it fires on every
machine for every player in the match. Played flat that would be twelve players'
building heard at once by all of them; played at the tower, the distance gate
decides whose maze anybody hears - which is the answer a player wants.

**A build REFUSED is flat and IS filtered.** There is no tower to play it at,
and the whole news is that there is not.

**Income is the payout, not every coin.** Gold also arrives as a bounty for
every creep that dies in your maze, which is a continuous drip in a working
match; a ping on each one says nothing a player cannot already see. The payout
is an event - it arrives on a clock and the whole economy is paced against it.

### Proving it

Audio cannot be checked by a headless run: `AudioHub` sets `_silent` on a
process with no output device and every call returns early, so a headless pass
is a test of the early return. It cannot easily be checked windowed either - a
windowed run spends its first thousand frames compiling shaders and a
frame-counted probe quits before the match has spawned anything.

What worked, and is worth repeating if this is ever touched again: force
`_silent` false, add a counter to `AudioHub._claim_gap`, and run a throwaway
probe HEADLESS against `Main.tscn` that builds a tower through the builder,
spawns creeps next to it, reports a leak through `Replication.report_leak` and
pays income. Then read the counter.

Three traps were paid for on the way, all of which read as "the audio does not
work":

- **A probe against `server_match.tscn` reports silence and is right to.** A
  dedicated server wires no `audio_config` on its `References` at all, so
  `MatchAudio` finds nothing and plays nothing. The client scene is `Main.tscn`
  and it is the only one worth probing.
- **A one-player match is won the instant it starts**, the summary screen
  changes the scene, and a probe that was the root node goes with it - which
  looks exactly like the audio never firing. Two players.
- **Starting gold is 0 in the default settings preset**, so a build ordered by a
  probe is refused on arrival. That is the `build_denied` path working
  perfectly and the `tower_placed` path never running.

The general form of all three is CLAUDE.md's rule about a positive control: ask
what in the output proves the thing under test actually executed. The counter
printing a sound's name is that proof; an absence of errors is not.

## 8. Not built yet

- **Music and ambience.** `AudioHub.play_music()` works and nothing calls it;
  `music_menu_path` and `music_match_path` are empty because there are no
  tracks. `AudioClipSet` and `IntervalClipSet` are authored and unused.
- **Five match events have no file**, so their paths are empty and they are
  silent rather than wrong: a tower sold, a life TAKEN off somebody else, a
  player eliminated, victory and defeat. Adding one is a sound in SfxGen's
  roster, a path in `audio_config.tres` and a call - the first two of the five
  already have somewhere obvious to be called from.
- **The voice budget is unmeasured.** The caps in `audio_config.tres` are
  starting guesses and `Scenes/Tools/perf_bench.tscn` is where they should be
  checked, against a full maze rather than against a probe.
- **The tier axis is unused.** SfxGen renders one sound per branch and scales
  nothing by tier, so an Ultimate fires with the same sample as the 10g tower
  under it. The table for it is already in `sounds.py`.
- **`AudioListener3D`** is not placed; world sounds use the camera as the
  listener by default.
- **Nothing is mixed**, with one exception. Every sound plays at whatever level
  SfxGen normalised it to: `AudioClipSet.volume_offset_db` is the authored place
  for a trim and nothing uses it yet, and no sound is balanced against any
  other. The first real listening pass will want per-sound trims before it wants
  anything else on this list.
  - the exception is `build_refused`, which is rendered 8 dB under the set's
    ceiling in `sounds.py`. It was reported as far too loud and measured that
    way: a bitcrushed square wave is dense across its whole band, so at the
    shared peak it sat 10 dB above the impacts, and being FLAT it is never
    pulled down by the distance attenuation that quietens everything in the
    world. Both halves of that are worth remembering the next time a flat sound
    is added.
  - **measure before trimming one.** Peak tells you nothing about loudness
    here; RMS over the loudest 50 ms window ranks the set in the order a person
    hears it, and a throwaway script over `Audio/` is a minute's work. Guessing
    a decibel number is how a sound ends up inaudible instead.
