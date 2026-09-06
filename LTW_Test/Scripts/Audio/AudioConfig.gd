class_name AudioConfig
extends Resource

## Every sound that has NO unit to hang off, plus the mixing rules.
##
## The line this file draws is worth stating, because the obvious version of
## this class is a flat list of every sound in the game and that version does
## not survive the roster. A tower's fire sound belongs on its AttackStats and a
## creep's death sound on its CreepStats, for the same reason a tower's gold
## cost lives on its BuildingStats: a stats resource is the authority on the
## thing it describes, and a value copied into a second file drifts. With ten
## element lines that list would be two hundred entries nobody can keep aligned
## with the roster.
##
## What is left is what genuinely belongs to nobody: the interface, and the
## match-wide events. Those have no stats resource to live on, and this is their
## home.
##
## PATHS, NOT STREAMS. Same rule and the same reasoning as a .tres naming a
## scene: an AudioStream held as an ext_resource is a hard load-time dependency,
## so loading this config would pull every sound in it into memory whether or
## not one is ever played. A path costs nothing until something asks for it.
## AudioHub owns the cache and the loading - see AudioHub.play_ui().
##
## Stored as Resources/Config/audio_config.tres, reached via
## References.audio_config.

@export_group("Interface", "ui_")
## The ordinary button press. Every BaseButton in the project plays this unless
## a ButtonSounds child says otherwise.
@export_file("*.wav", "*.ogg") var ui_click_path: String = ""
## Mouse entering a button that can be pressed.
@export_file("*.wav", "*.ogg") var ui_hover_path: String = ""
## A press that landed on a DISABLED button.
##
## The most useful sound in the set and the one most projects never have: it is
## the answer to "why did nothing happen", and without it a greyed-out command
## card is indistinguishable from a broken one.
@export_file("*.wav", "*.ogg") var ui_refused_path: String = ""

@export_group("Building", "build_")
## A tower finished being placed.
@export_file("*.wav", "*.ogg") var build_placed_path: String = ""
## A placement the world refused: no gold, no stock, or it would have sealed
## the maze. Distinct from ui_refused, which is about a BUTTON.
@export_file("*.wav", "*.ogg") var build_denied_path: String = ""
## A tower sold.
@export_file("*.wav", "*.ogg") var build_sold_path: String = ""

@export_group("Match", "match_")
## Gold arriving, whether from income or from a bounty.
@export_file("*.wav", "*.ogg") var match_gold_path: String = ""
## A creep reached the end of your lane and took a life.
##
## Has to be understood while the player is looking somewhere else, which is
## most of the time - see the note in SfxGen's sounds.py.
@export_file("*.wav", "*.ogg") var match_life_lost_path: String = ""
## You are the one who took a life off somebody else.
@export_file("*.wav", "*.ogg") var match_life_taken_path: String = ""
## A player was knocked out.
@export_file("*.wav", "*.ogg") var match_eliminated_path: String = ""
## The match ended and you won it.
@export_file("*.wav", "*.ogg") var match_victory_path: String = ""
## The match ended and you did not.
@export_file("*.wav", "*.ogg") var match_defeat_path: String = ""

@export_group("Music", "music_")
## Plays under the menus.
@export_file("*.wav", "*.ogg") var music_menu_path: String = ""
## Plays during a match.
@export_file("*.wav", "*.ogg") var music_match_path: String = ""
## Seconds a music change takes to cross over. 0 cuts.
@export_range(0.0, 8.0, 0.1) var music_fade_seconds: float = 1.5

@export_group("Voice budget", "budget_")
## How many WORLD sounds may play at once.
##
## **This is the setting that decides whether a full match is playable.** Every
## tower in every lane fires on the same twenty-per-second tick, so the honest
## upper bound on requests per second is in the thousands and the only question
## is how many of them are allowed through. When the budget is full a new sound
## takes a voice only if it is CLOSER to the camera than the furthest one
## playing - see AudioHub._claim_world_player().
##
## 32 is a starting guess, not a measured number. Measure it with a full maze
## before trusting it.
@export_range(4, 128, 1) var budget_world_voices: int = 32
## How many INTERFACE sounds may play at once. Small on purpose: the UI is one
## player clicking, and anything that needs more than this is a bug.
@export_range(2, 32, 1) var budget_ui_voices: int = 8
## The shortest gap between two plays of THE SAME sound, in seconds.
##
## The dedupe that makes a maze survivable. Forty towers of one type firing on
## one tick is forty requests for one .wav inside a millisecond, which sums to
## noise and forty times the amplitude rather than to forty audible shots. One
## gets through and the rest are dropped.
@export_range(0.0, 0.5, 0.005) var budget_same_sound_gap: float = 0.04
## The same idea for hover, which needs a much longer gap: a command card is a
## grid, and one mouse sweep crosses a dozen buttons in a few frames.
@export_range(0.0, 1.0, 0.01) var budget_hover_gap: float = 0.06

@export_group("World sound", "world_")
## How far away a world sound is still audible, in metres.
##
## The camera sits about 12 m up, so this is a few screens rather than a few
## metres. A sound beyond it is not merely quiet, it is skipped before a voice
## is spent on it, which is most of what keeps twelve lanes affordable.
@export_range(4.0, 200.0, 1.0) var world_max_distance: float = 45.0
## Metres over which a world sound is at full volume before it starts falling
## away. Godot's own attenuation takes over past it.
@export_range(0.5, 40.0, 0.5) var world_unit_size: float = 9.0
## Decibels taken off a sound playing in a lane the player is NOT looking at.
##
## Twelve lanes all at full volume is noise, and the answer is not the mixer -
## it is that a sound you cannot see is worth less than one you can. 0 disables
## the rule entirely, which is the honest way to hear what it is buying.
@export_range(-60.0, 0.0, 1.0) var world_offscreen_db: float = -14.0
