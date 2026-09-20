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
## **EVERY SOUND BELOW SAYS WHETHER IT IS IN THE WORLD OR NOT**, because that is
## the one thing about a sound that cannot be worked out by looking at it later,
## and it decides which of two completely different calls plays it:
##
##   WORLD  happens at a point, is heard from where the camera stands, and is
##          attenuated, culled by distance and budgeted. AudioHub.play_at().
##   FLAT   happens to the MATCH rather than to a place in it, and is heard the
##          same wherever the player is looking. AudioHub.play_event(), or
##          play_ui() when it is about a control rather than about the match.
##
## Getting it wrong is silent both ways round: a flat sound written as a world
## one is never heard at the moment it mattered, and a world sound played flat
## is every lane in a twelve player match shouting at once.
##
## THE TWO CREEP DEFAULTS are the one place this file names something a stats
## resource could own, and they are deliberate. A DEFAULT is one entry, not a
## roster - it is what a creep that names nothing sounds like, and the moment a
## creep wants its own it says so on its own CreepStats and this is not
## consulted. That is the opposite of the two hundred entry list the rule above
## exists to prevent.
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
## **FLAT**, and on the UI bus rather than SFX - the interface is a channel a
## player may want quieter without turning the game down.
##
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
## **WORLD.** A tower landed on the grid, played where it landed.
##
## In the world rather than flat, although it is the player's own doing: under
## lockstep every client simulates every lane, so this fires on every machine
## for every player in the match. Played flat it would be twelve players'
## building heard at once by all of them; played at the tower it is heard by
## whoever is looking at that maze, which is what a player wants to know.
@export_file("*.wav", "*.ogg") var build_placed_path: String = ""
## **FLAT.** A placement the world refused: the spot was taken while the
## builder walked, or the gold ran out before it arrived.
##
## Distinct from ui_refused, which is about a BUTTON that could not be pressed.
## This one is the order itself coming to nothing, seconds later and usually
## while the player is already doing something else - which is exactly why it
## cannot be positional. Played for the LOCAL player's own refusals and nobody
## else's; see MatchAudio.
@export_file("*.wav", "*.ogg") var build_denied_path: String = ""
## **WORLD.** A tower sold, played where it stood. NOT WIRED: there is no file
## for it yet.
@export_file("*.wav", "*.ogg") var build_sold_path: String = ""

@export_group("Match", "match_")
## **FLAT.** The income payout landing.
##
## THE PAYOUT AND NOT EVERY COIN, which is a decision rather than an oversight.
## Gold also arrives as a bounty for every creep that dies in your maze, and
## that is a continuous drip in a working match - a ping on each one says
## nothing a player cannot already see, and at twenty ticks a second it is a
## machine gun. The payout is an EVENT: it arrives on a clock, the whole
## economy is paced against it, and hearing it is how a player knows the
## interval turned over without watching the timer.
@export_file("*.wav", "*.ogg") var match_gold_path: String = ""
## **FLAT.** A creep reached the end of your lane and took a life.
##
## Has to be understood while the player is looking somewhere else, which is
## most of the time - see the note in SfxGen's sounds.py. That is the whole
## argument for this being flat rather than played at the end zone it happened
## in: the lane it happened in is precisely the one nobody was watching.
@export_file("*.wav", "*.ogg") var match_life_lost_path: String = ""
## **FLAT.** You are the one who took a life off somebody else. NOT WIRED:
## there is no file for it yet, so a leak you profited from is silent rather
## than borrowing the sound of one you suffered.
@export_file("*.wav", "*.ogg") var match_life_taken_path: String = ""
## **FLAT.** A player was knocked out. NOT WIRED: no file yet.
@export_file("*.wav", "*.ogg") var match_eliminated_path: String = ""
## **FLAT.** The match ended and you won it. NOT WIRED: no file yet.
@export_file("*.wav", "*.ogg") var match_victory_path: String = ""
## **FLAT.** The match ended and you did not. NOT WIRED: no file yet.
@export_file("*.wav", "*.ogg") var match_defeat_path: String = ""

@export_group("Creep defaults", "creep_")
## **WORLD.** What a creep dying sounds like when its own CreepStats names
## nothing, played where it died.
##
## A DEFAULT rather than a list, which is why it is allowed in this file at all
## - see the note at the top. The roster shares one death sound today, and a
## creep that wants its own says so on its own stats resource without anything
## here changing.
##
## EMPTY here means the WHOLE ROSTER is silent when it dies, not one creep -
## which nothing wants. It is the feedback that says the maze is working, and
## the one sound a player must never have to look at the screen to identify.
@export_file("*.wav", "*.ogg") var creep_death_path: String = ""
## **WORLD.** A freshly sent creep arriving, on the same terms. A RECYCLED
## creep - one walking on into the next maze after a leak - is not a spawn and
## does not play this.
@export_file("*.wav", "*.ogg") var creep_spawn_path: String = ""

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
## How many FLAT sounds may play at once, the interface and the match events
## together - they share one pool, see AudioHub._claim_flat_player().
##
## Small on purpose: flat sounds are one player clicking and a handful of match
## events a minute, so anything needing more than this is asking faster than a
## person can act.
@export_range(2, 32, 1) var budget_flat_voices: int = 8
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
