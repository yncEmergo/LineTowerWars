# What's this project?
- 3d game
- The goal is to make a standalone version of the Warcraft III custom Map "Line Tower Wars"
- It's a PvP tower defence game with 2-15 players where players have to send creeps and defend against creeps from other players
- Game name: to be decided.
- The first major milestone and for now the only one is a prototype where 1v1 gameplay can be tested. No need for 3+ player FFA gameplay yet-

# Hard rules
- you're here to implement the game not design it
- do NOT alter the rules unless on your own without asking
- use Log.gd addon for debugging
- NO PHYSICS ENGINE. Every gameplay result is computed in plain maths, never by
  a physics body, a collision shape or a space query
  - no CharacterBody3D / RigidBody3D / Area3D for gameplay, no move_and_slide,
    no intersect_ray, intersect_shape or direct_space_state
  - units are plain Node3D and move by writing their own position
  - projectiles are heat-seeking: they steer toward a target each tick and hit
    when close enough. No ballistics, no collision callback. An arc_height is
    a purely visual curve laid over that path
  - picking a unit under the cursor is camera projection maths
    (SelectionController.unit_at), not a raycast
  - this is a HARD rule, not a preference. The server is authoritative and runs
    the same simulation headless, where a physics engine is both unavailable in
    spirit and a source of machine-to-machine drift. See multiplayer.md
- ONLY THE AUTHORITY SIMULATES. Every gameplay loop starts with
    if !MatchSession.is_authority():
        return
  A client runs no simulation of its own: it draws the world the server sends it
  (multiplayer.md 3.4). Anything new that advances the world - moves a unit,
  spends gold, ticks a timer, applies damage - must ask, or the client will
  compute something the server also computes and the two will disagree
  - presentation is the exception and stays local: selection, the build ghost,
    order markers, the range overlay, and the attack/projectile visuals. An
    ability that is presentation says so with is_local_only()
- A player order is never executed directly. It goes through Commands.submit(),
  which sends it to the server; the server checks ownership and the card, then
  runs the same ability.execute() a single player run would. Never re-implement a
  rule the simulation already enforces - gold, stock, placement legality and the
  maze-blocking rule are refused by the world itself
- Anything that crosses the wire is named by an AUTHORED id, never by a path, an
  index or a name: UnitAbility.ability_id and UnitStats.unit_type_id. Both are
  scanned out of the folders ContentConfig names, so an orphan still owns its
  number and nothing can be authored into a taken one
- An @rpc endpoint must be an AUTOLOAD. Godot routes rpcs by node path, and the
  client's match scene root is /root/Main while the server's is /root/ServerMatch,
  so no node inside a match scene can receive one

# Code/Syntax & Naming conventions
- Be as typesafe as possible
  - never use ":=" in declarations, always write the type out: var time: float = 3.0
  - type function parameters and return values too: func move_to(target: Vector3) -> void
- Always write "&&", "!" and "||", never the "and", "not" and "or" keywords
  - the two-word operators "is not" and "not in" are the one place the word survives,
    and they must be rewritten rather than swapped: !(x is Type), !(x in y). Replacing
    just the "not" gives "is !Type", which does not parse
- References between nodes and classes always use @export
  - never use @onready
  - never use $ node paths
  - cross-class references go through Scripts/References.gd: a Node placed in the scene
    that holds every manager and config as @export and exposes them as static getters,
    reached as References.game_config, References.rts_camera and so on
  - always use References when it already holds what you need, never wire a second
    @export to the same thing. If something shared is missing from References, add it
  - a node's own children and its own assets stay plain @export: its labels and meshes,
    the prefab it spawns, the stats resource of that one unit type
  - a node held by References may read References back, the mutual dependency is fine
  - when a script reads the same References entry more than once or twice, give it a
    getter property rather than repeating References.x everywhere:
      var _config: GameConfig:
          get:
              return References.game_config
- Game-relevant settings belong in config resources (.tres), never in scripts
  - camera settings, unit stats, balancing values, match rules
  - example: Resources/Config/camera_config.tres backed by Scripts/Config/CameraConfig.gd
  - only visual reference values stay in scripts as constants: placeholder mesh sizes,
    UI positions and offsets, placeholder colors
  - exception: a setting the engine reads before the game starts stays in
    project.godot. Two so far:
    - gui/timers/tooltip_delay_sec, which the Viewport reads in its
      constructor. Pushing it from a .tres at runtime is silently ignored,
      verified both ways
    - physics/common/physics_ticks_per_second (20), which IS the simulation
      tick rate - every gameplay loop lives in _physics_process and nothing
      gameplay-relevant happens on a render frame. Paired with
      physics/common/physics_interpolation for smooth rendering between ticks.
      See multiplayer.md
- A resource NEVER holds a PackedScene. It names the scene by res:// path
  - `@export_file("*.tscn") var thing_scene_path: String`, loaded on first use
    and cached on the resource
  - a PackedScene inside a .tres is a hard load-time dependency: Godot aborts the
    WHOLE resource when one ext_resource is missing, so a deleted prefab silently
    nulls every property of the file that referenced it, and of anything holding
    that file. Cost us a whole debugging session once
  - a path fails loudly, on its own, at the point of use, and makes a reference
    cycle impossible - which is what lets a stats resource name its own prefab
    while that prefab points back at the stats through its own @export
  - the editor does NOT rewrite a path string when a scene moves or is renamed,
    so every declared path is checked once at boot by Main._validate_content
  - NODES keep plain PackedScene @exports: their scenes are their own assets,
    wired in the same .tscn, and the editor does keep those references up to date
- A stats resource is the authority on the thing it describes, and names its own prefab
  - an ability points at the STATS, never at the prefab, so nothing ever has to
    spawn a unit to find out what it costs. No instantiate-and-free probes
- A cost or stat belongs to the thing it describes, never to the ability that buys it
  - a tower's gold cost lives on its BuildingStats, a creep's on its CreepStats
  - the ability reads it off that stats resource, so a number cannot drift
    between two files
- Abilities are Resources carrying their own behaviour, and they are SHARED
  - one send_basic_creep.tres is the same object for every unit referencing it
  - so an ability must never hold per-unit state: no cooldowns, charges or counts
  - that state belongs on the unit: the send building owns its creep stock
  - a value derived only from the ability's own @exports may be cached on it,
    since every user of that resource would compute the same answer
- The same shape is used for anything else that carries behaviour as data. An
  attack is the worked example, in Scripts/Combat:
  - one exclusive choice is a polymorphic resource, never a bool. Which
    AttackDelivery subclass an attack holds IS the answer to "is it a
    projectile", so no flag has to be
  - anything that stacks is an Array of resources. Splash, chain and slow are
    entries in AttackStats.effects, not three more flags to combine
  - do not reuse UnitAbility for these. An ability is a command card entry and
    owns a hotkey, an icon and a targeting mode. An on-hit effect owns none
- Use @export_group for grouping variables
  - "References" and "Settings" are the default groups in most classes
- Naming
  - scripts and folders in PascalCase: Scripts/GameManager.gd, Scripts/Config/CameraConfig.gd
  - resources and scenes in snake_case: main_menu_ui.tscn, game_config.tres
  - every script gets a class_name matching its file name, even if nothing references it yet
- Other than that use the official Godot styleguide (might add some exceptions later)
  - declaration order: class_name, extends, docstring, signals, enums, constants,
    @export vars, public vars, private vars, then methods
  - max line length is 100 characters
- If anything is unclear, please just ask and I'll add it to the Claude.md


# Writing scenes and resources by hand
- A node with node-typed @exports needs node_paths=PackedStringArray("_field", ...)
  on its [node] line, or those references silently stay null at runtime
- Never invent a uid. Omit it, or reference by path only, and let Godot assign one
- A child node's _ready runs BEFORE its parent's, and Godot refuses to give a node
  a child while that node is still setting its own up. So a component cannot add a
  node to its own unit from _ready - build it lazily on first use instead
- The editor rewrites hand-written files when it saves them, so re-check exports
  afterwards if the scene has been opened
- Saving a .tres from the editor also drops every property that equals its script
  default, so a hand-written file loses the lines that only restated defaults.
  Nothing is lost, those values still read back the same
  - so where the .tres is the authority for real data, leave the script default
    empty. A default matching the file would be stripped from it on the next
    save, quietly moving the data into the script. DamageTable does this
- In a .tres, every property must come AFTER the "script = ExtResource(...)" line.
  A property written above it is applied to the plain Resource and then thrown
  away when the script replaces it - silently, with no warning and no error. Cost
  a debugging cycle: fourteen unit_type_ids all read back as 0
- An override must call super() unless it really means to replace the parent
  entirely. Godot calls only the MOST DERIVED _ready/_exit_tree/_physics_process,
  so a subclass that forgets shadows the base one. Building._exit_tree did, and
  every tower ever sold leaked its entry in the unit registry
- _set, _get, _notification and friends are Object's own virtuals. A private
  helper named _set() fails to parse with "signature doesn't match the parent"
- gdlint runs in the editor. It does not understand @abstract, so that parse warning
  is noise. It also caps public methods per class at 20 and returns per function
  at 6
- NEVER edit [autoload] in project.godot while the editor is open. The editor
  holds its own copy of ProjectSettings, does not re-read the file, and a
  filesystem scan does not help - every autoload added from outside is
  "Identifier not found" until the editor is restarted. Headless runs are
  unaffected, which is what makes it confusing

# Testing
- Verify cheaply, then hand the rest over
  - boot the project once to confirm it loads with no errors
  - check whatever a single call can answer: node properties, one screenshot
  - anything timing- or feel-dependent goes to the user as a short test checklist
- The MCP tools can drive the running game, with limits worth knowing up front
  - clicking works, and command card slots can be clicked by their rect from
    get_ui_elements, which is steadier than hoping a hotkey lands
  - a key press and its release are separate calls seconds apart, so any ability
    with repeat_on_hold fires dozens of times. Expect that, or do not use keys
  - tens of seconds of game time pass between two calls. Nothing that lasts under
    a second - a projectile in flight, one attack - can be caught by polling for
    it, so do not spend calls trying. Prove those from state that persists, or
    hand them over
  - what DOES catch a short effect: press the key, screenshot WHILE IT IS STILL
    HELD, then release. repeat_on_hold fires for the whole gap, so the shot lands
    mid-flood with creeps spawning and dying in view. Screenshotting after the
    release always shows an empty lane, because the flood ended a call ago
    - put the tower at the top of the lane, under the spawn zone, so kills happen
      in view rather than seven seconds of walking away
    - even so, under ~2 seconds is out of reach, and a click can almost never be
      landed on a moving creep: they cover ~26 cells between two calls
  - logs_read(source="game") times out on this project, the Log.gd volume
    saturates the buffer. source="editor" works and is where parse errors,
    push_error and the boot-time resource failures land
  - that includes Log.err from the RUNNING GAME, which reaches source="editor"
    with a full GDScript stack trace, usually only after the run is stopped.
    So the game IS observable: to check something with no visible effect,
    temporarily Log.err it, or deliberately break the data and confirm the
    exact error. Cap any per-frame probe with a counter or push_error floods
  - editor errors are RETAINED across runs, so a stale one keeps appearing.
    Trust current_run_errors from project_run over the raw log, and prefer
    reading with offset rather than since_cursor, which can return nothing
    while entries exist
  - after changing a function SIGNATURE the editor keeps the old parse and
    reports a bogus "Too many arguments" at the call site. stop() then
    filesystem_manage(op="scan") clears it; reimport does not
  - a negative result only counts if the test exercised the right case. A probe
    that never fires because the wrong unit was spawned looks identical to a
    probe that disproves the theory
- Never inflate a gameplay value to fit a test, and never leave one inflated
- The multiplayer test loop that actually works is HEADLESS AND SCRIPTED, not the
  editor. Godot instances driven by hand cannot be made to do the same thing
  twice, and the MCP tools cannot drive two clients at once
  - start the server with run_server.ps1, then launch N clients as
    godot --path <project> --headless -- --probe <role>
  - drive them from a TEMPORARY autoload under Scripts/Dev that reads its role
    off the command line and does nothing at all when --probe is absent, so the
    server and the editor are unaffected by its presence
  - a probe that has to survive a scene change must be an autoload; one that only
    needs to set a match up can be a scene that instances Main.tscn as a child
    after parking a MatchSetup in MenuNavigation.pending_match
  - DELETE Scripts/Dev and Scenes/Dev when the work is done, and remove the
    autoload line. They are scaffolding, not tests
  - stop and restart the server between runs. A lobby left over from the last one
    looks exactly like a bug in the next

# Tech
- Godot game engine version 4.7
- Targeting pc (Keyboard & Mouse)

# Project structure
- /2DArt/ contains all textures
- /3DArt/ contains all Meshes
- /Scripts/ contains all gd scripts
- /Scenes/ contains all scenes
- /Resources/ contains all resources
- /Audio/ contains all sound files

# Other
- README.md is the way in: what the project is, what works, and which file answers
  what. Keep its Status section honest - it is the first thing a new reader trusts.
- Refer to game_rules.md for the rules. It says which rules are BUILT and which
  are only written down; keep that marking correct when you implement one.
- multiplayer.md holds the multiplayer working notes and its open questions.
- server.md is how to start, stop and aim the dedicated server. Controls only, not
  architecture. KEEP IT UPDATED whenever the server gains or loses a control.
- claude_notes.md is a stale duplicate of the conventions above. Ignore it.

# Known weaknesses
Real, none blocking. Recorded so they are not rediscovered as surprises.
- PlayerArea.gd is at 29 public methods against gdlint's ceiling of 20, and
  Unit.gd at 21. Intended fix for the first: extract the grid half - occupancy,
  cell maths, flow field - into an AreaGrid it owns. Touches Building, Builder,
  BuildGrid, CommandController. Not started
- Three naive linear scans over an area's creeps: creep separation, TargetFinder,
  and Creep._refresh_aura. One spatial hash fixes all three
- Replication sends the whole world every tick, roughly 36 bytes per unit at
  20 Hz. Fine for a 1v1 on a LAN, nowhere near 15 players. That is multiplayer.md
  3.3, deliberately deferred until there was something to measure
- Dead content, safe to delete on the user's word: Scenes/basic_tower.tscn,
  Scenes/basic_tower_stats.tres, Resources/Abilities/build_basic_tower_ability.tres,
  Scenes/Units/basic_creep.tscn, Resources/UnitStats/basic_creep_stats.tres,
  Resources/Abilities/send_basic_creep_ability.tres. Sniper and Sheep replaced
  them. basic_tower_stats.tres also sits in Scenes/ rather than
  Resources/UnitStats/, so the unit type registry never sees its id
- Two traps not covered by the rules above: SelectionController._select_in_rect
  must FALL THROUGH when the box caught neither a commandable unit nor a creep,
  or an empty box stops clearing the selection; and AttackRangeOverlay.MAX_CIRCLES
  must match the const in Resources/Shaders/attack_range.gdshader

# Look & setting
- To be decided
