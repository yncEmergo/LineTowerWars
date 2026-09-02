# What's this project?
- 3d game
- The goal is to make a standalone version of the Warcraft III custom Map "Line Tower Wars"
- It's a PvP tower defence game with 2-12 players where players have to send creeps and defend against creeps from other players
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
  - the NUMBER itself carries no meaning. There is no block plan and no range
    that implies a kind: ids were handed out in creation order and any gap or
    grouping in them is an accident. Do not read one, and do not preserve one
  - what an id must be is UNIQUE within its own namespace and PERMANENT once
    authored. ability_id and unit_type_id are separate namespaces
  - to pick the next one, scan the folder and take the highest plus one. The
    registry refuses a duplicate loudly at boot, so a collision is a failed boot
    rather than a bug that ships
  - ints rather than guids on purpose: an id is read by a human in a .tres, in a
    server rejection line and in a log, and a guid would cost that for a
    uniqueness the registry already enforces
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
    project.godot. So far:
    - gui/timers/tooltip_delay_sec, which the Viewport reads in its
      constructor. Pushing it from a .tres at runtime is silently ignored,
      verified both ways
    - physics/common/physics_ticks_per_second (20), which IS the simulation
      tick rate - every gameplay loop lives in _physics_process and nothing
      gameplay-relevant happens on a render frame. Paired with
      physics/common/physics_interpolation for smooth rendering between ticks.
      See multiplayer.md
- A resource REFERENCES a scene BY res:// PATH, never by holding a PackedScene
  - `@export_file("*.tscn") var thing_scene_path: String`, loaded on first use
    and cached on the resource
  - **this is a PERFORMANCE rule.** A PackedScene inside a .tres is a hard
    load-time dependency, so loading the resource loads the scene, and
    everything that scene reaches, whether or not any of it is ever used.
    Touching one tower's stats to read its gold cost would pull its prefab, its
    model, its meshes and its materials into memory. A path costs nothing until
    something actually spawns from it
  - it is also what makes a reference CYCLE impossible, which is what lets a
    stats resource name its own prefab while that prefab points back at the
    stats through its own @export
  - and a missing scene then fails loudly, on its own, at the point of use,
    rather than taking its whole .tres down with it - Godot aborts the WHOLE
    resource when one ext_resource is missing, so a deleted prefab would
    silently null every property of the file that referenced it
  - the cost is that the editor does NOT rewrite a path string when a scene
    moves or is renamed, so every declared path is checked once at boot by
    Main._validate_content
  - a path is HARDER TO FOLLOW in the inspector than a resource slot, since it
    draws as a text field. Where that matters, surface it: see
    AttackComponent, which shows a tower's projectile and impact scenes as
    read-only slots you can click
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
  - one send_sheep_ability.tres is the same object for every unit referencing it
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
- A PanelContainer's padding lives in its StyleBox content margins, never in a
  MarginContainer inside it. Both do the same job, so a panel carrying both double
  dips and its real padding is spread across two files
  - a StyleBoxFlat that sets no content_margin does NOT mean zero: each side falls
    back to that side's border width, so a bordered panel silently adds to whatever
    the MarginContainer asks for, and the number authored is not the number drawn.
    Cost a pass over unit_panel.tscn once
  - two panels wanting different padding then need two styleboxes, which repeats
    the colour and border between them. Worth it: padding is what gets tuned, the
    look is not
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
- process_priority does NOT order _physics_process. Godot 4.3 split the two:
  process_priority orders the RENDER frame, process_physics_priority orders the
  TICK. A node that sets only the first and expects to simulate last runs in
  plain tree order instead, silently
  - which for an AUTOLOAD means BEFORE the whole match scene, since autoloads
    are added to root first. ReplicationService had exactly this and was
    building its snapshot from the previous tick
  - set BOTH when a node has to be last, and remember that a node whose parent
    is the thing it is timing runs before it by default
- A NEW SCRIPT IN AN EXISTING FOLDER is not imported by a `godot --path` run. A
  new FOLDER is scanned; a new file dropped into a folder Godot already knows is
  not. Its class_name never reaches the global class cache, so every script
  naming it fails with "Identifier ... not declared in the current scope" -
  which reads exactly like a typo in a file that is plainly correct
  - `godot --path <project> --headless --import` fixes it, and the editor does
    it on its own when it notices the file. Check
    `.godot/global_script_class_cache.cfg` to confirm which it is

# Testing
- Verify cheaply, then hand the rest over
  - boot the project once to confirm it loads with no errors
  - check whatever a single call can answer: node properties, one screenshot
  - anything timing- or feel-dependent goes to the user as a short test checklist
- The MCP tools can drive the running game, with limits worth knowing up front
  - clicking works, and command card slots can be clicked by their rect from
    get_ui_elements, which is steadier than hoping a hotkey lands
    - send an input_mouse MOTION to the rect BEFORE the press. Without it the
      first press on a button can fall straight through to the world - the
      click selects a unit instead, which reads exactly like a dead button.
      Cost a round of second-guessing the Research Center's footer buttons
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
  - start the server with Tools/run_server.ps1, then launch N clients as
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
Where a kind of file goes. Some of these folders do not exist yet - there is no
art at all so far - so this is the placement rule, not a description of the tree.
- THE ROOT holds only what something outside the project looks up by name:
  CLAUDE.md, README.md, project.godot and the dotfiles. Nothing else belongs
  there - a new .md goes in /Docs/ and a new script in /Tools/
- /Docs/ is every reference document except this one and the README, with
  /Docs/Findings/ for written-up investigations. /Docs/README.md is the index
  and says where a new document goes
- /Scripts/ contains all gd scripts, split by area
- /Scenes/ contains all scenes, split by area
- /Resources/ contains all resources, split by kind: Config, UnitStats,
  Abilities, Materials, Shaders, UI
- /2DArt/ contains all textures
  - /2DArt/Icons/ is GENERATED placeholder art: one render per unit type, baked
    from that unit's own model. Do not hand-edit one, it is overwritten
  - /2DArt/UI/Icons/ is the HUD's own glyphs, flat white silhouettes so that
    CommandSlot can tint them. stat_* was drawn by hand; ability_* is generated
    by Tools/IconGen and is overwritten the same way
- /3DArt/ contains all meshes
- /Audio/ contains all sound files
- /Scripts/Tools/ and /Scenes/Tools/ are tooling that has to RUN INSIDE GODOT,
  which is why it is not in /Tools/ with the rest - a `.gdignore` keeps Godot
  out of that folder entirely, so a scene cannot live there
  - so far one thing: Scenes/Tools/icon_gen_3d.tscn, which bakes a unit's icon
    by rendering its own model and so cannot go headless. It scans the stats
    folder rather than carrying a roster, and `-- new` bakes only what has no
    picture yet
  - KEPT, not scaffolding. Scripts/Dev is the folder that gets deleted; this is
    run again every time a roster gains a unit
- /Tools/ is BUILD TIME TOOLING that never runs inside the engine, and is not
  part of the game. Nothing at runtime may reach into it, and a `.gdignore`
  keeps Godot's filesystem out
  - the CONTROL SCRIPTS live at the top of it: run_server.ps1, stop_server.ps1
    and run_bench.ps1. They are typed FROM THE PROJECT ROOT
    (`.\Tools\run_server.ps1`), and each works out the project folder as its own
    parent - so one moving deeper needs that line changed, not just the call
  - Tools/ModelGen generates the placeholder art: the tower models, the
    materials they share, their projectiles, and the .tres content pointing at
    all of it. Its output is checked in and is ordinary hand-editable Godot, so
    editing a generated file is fine - the next run just overwrites it
  - it is where the tower visual language actually lives as code. If a tier
    rule or a palette changes, change it there and re-run rather than editing
    thirty scenes. Tools/ModelGen/README.md has the layers and how to run it
  - **before building placeholder visuals for a new roster - the elemental
    towers, the creeps - read Tools/ModelGen/PLACEHOLDER_ART.md.** It is the
    design philosophy the tower roster was built to, the contracts a model has
    to meet, how to verify the result, and the traps that have already been
    paid for. It is the file that stops the next roster looking like a
    different game
  - it is deliberately NOT Scripts/Dev: that folder is scaffolding to delete,
    this is a tool to keep
  - Tools/IconGen is the second tool, and draws the command card ACTION icons -
    Move, Stop, Attack, Sell, Build, Cancel - into 2DArt/UI/Icons. Same shape as
    ModelGen: stdlib Python, run from the project root, output checked in.
    Tools/IconGen/README.md has the style rules a new glyph has to meet
  - an ability that ModelGen owns takes its icon through action_icon_path() in
    element_content.py or tower_content.py. Wiring one by hand into the .tres
    instead is silently thrown away by the next ModelGen run
- A UI element that will gain behaviour later - a command slot, an ability
  button - is a prefab scene, never a node built in code

# Other
- **THE REFERENCE DOCS LIVE IN `Docs/`, and the control scripts in `Tools/`.**
  Only this file and README.md are still in the root, and both are there because
  something outside the project looks for them by name: Claude Code loads this
  one, and a git host renders that one
  - so a comment anywhere saying "see game_rules.md" means `Docs/game_rules.md`.
    Comments name the DOCUMENT, not the path, and there are hundreds of them -
    they were deliberately left alone when the folder was made rather than
    rewritten into a diff across the whole codebase
  - `Docs/README.md` is the index: which file answers what, and where to write
    something new. Read it before adding a .md anywhere
  - `Docs/Findings/` is where an INVESTIGATION is written up - something that was
    measured, dug into or ruled out, rather than a rule or a number. It is the
    one place a dated snapshot of live values is allowed, because the date is
    what makes it honest. See its README for the shape
- GIT IS THE USER'S. Never commit, never push, never branch, never revert. Leave
  the work in the working tree and say what changed; the user reads it before it
  lands. Reading git - log, diff, blame, status - is fine and often useful
- README.md is the way in: what the project is, what works, and which file answers
  what. Keep its Status section honest - it is the first thing a new reader trusts.
- Refer to game_rules.md for the RULES - how the game works, not what anything
  costs. It says which rules are BUILT and which are only written down; keep that
  marking correct when you implement one. It never restates a number that
  unit_data.md already carries, it points there instead.
- unit_data.md holds the NUMBERS: every tower, creep, disc and technology of
  Warcraft III Line Tower Wars 12.4a, whose balance the prototype copies as
  closely as it can. It is the second and last .md allowed to carry stat tables,
  on the same grounds as game_rules.md: those numbers ARE the design being
  copied. Once a unit is implemented its .tres is the authority and unit_data.md
  is the mirror - change both in the same commit, until the generator in its
  section 8 makes that automatic.
- multiplayer.md is what the networked build is and where each part of it lives.
- server.md is how to start, stop and aim the dedicated server. Controls only, not
  architecture. KEEP IT UPDATED whenever the server gains or loses a control.
- NEVER write a COUNT or a live value into a .md file. No "26 abilities", no
  "13 unit types", no "29 public methods", no stat quoted out of a .tres. They
  are true for a day and misleading afterwards, and keeping them current is
  tedious work that buys nothing
  - the code is the authority on how many of a thing there are, and a reader who
    needs the number can boot the game or read the folder
  - write what is DURABLE instead: the mechanism, the rule, the id. An authored
    id (ability_id, unit_type_id) is stable by design and may be named freely
  - game_rules.md and unit_data.md are the only exceptions, and only for values
    they DECIDE or COPY FROM THE SOURCE GAME: the creep roster, the damage table,
    starting lives, the LTW 12.4a stat tables. Those numbers are the design, not a
    restatement of the code. Nothing else may copy them
  - a game design document may take that job over later. Until then no other .md
    grows a stats table
- NEVER write the CURRENT VALUE of a tuning knob into a .md file either. Whether
  creep separation is on, what starting_gold is set to today, which constant is
  temporarily cranked up for a test - all of it changes without warning and the
  .md is never the file that gets changed with it
  - the scripts and the .tres are well commented and are the authority. A .md
    that repeats them is a second copy that only ever goes stale
  - some overlap between the .md files and the code is unavoidable and fine. The
    test is whether the line would survive somebody editing the value: the RULE
    survives, the READING does not
  - the exception is something NOT YET IMPLEMENTED. A .md is the only place that
    can live, and it is exactly what a .md is for
- NEVER write a HOTKEY or a CARD SLOT into a .md file. Not which letter an
  ability answers to, not which square it claims, not the rows of letters
  themselves. The .tres is the single source of truth for both, and a .md
  naming one is a contradiction waiting to happen the next time a card is
  relaid out
  - the RULE survives and is worth writing: that the key is read off the
    POSITION, that a passive never takes a square worth pressing, that the
    Cancels share one square wherever you are. The POSITION does not
  - "the same square on every card" is durable. "the bottom left square" is a
    reading of today's .tres and goes stale silently
  - this covers generated content too: where ModelGen writes the slot, THAT
    line is the authority and a hand edit to its output is overwritten on the
    next run. Change the generator

# Known weaknesses
Real, none blocking. Recorded so they are not rediscovered as surprises.
- UnitAbility.gd is over gdlint's public-method ceiling, and went over when
  orders became chainable: an ability now also answers whether it can be
  queued, whether the task it started is finished, and gets a per-tick hook to
  steer one. Those four are the smallest honest shape for it - the alternative
  was a polymorphic OrderTask resource per ability, which is a .tres and a
  layer of indirection for the three abilities that would ever hold one. Worth
  revisiting only if a fourth kind of order arrives
- PlayerArea.gd and Unit.gd are both over gdlint's public-method ceiling,
  PlayerArea.gd by a lot. Intended fix for it: extract the grid half - occupancy,
  cell maths, flow field - into an AreaGrid it owns. Touches Building, Builder,
  BuildGrid, CommandController. Not started
- Creep.gd gained three more public methods with tier 2's creep mana - the pool
  itself, its second-resource reading and the per-creep clock a timed passive
  advances. The pool is already an object the creep owns (CreepMana) rather
  than three fields on it, which is the same shape the Building fix below wants
- Building.gd, Creep.gd and Combat/StatusEffects.gd are over that ceiling too,
  and all three for the same reason: they gained the elemental roster's
  machinery. Building took mana, StatusEffects is a wall of small questions
  about one creep, and Creep grew the four calls that reach it. Intended fix for
  Building: a TowerMana object it owns, the way it already owns ability_state.
  StatusEffects is a bad candidate for splitting - the whole point of it is that
  a caller asks one object everything
  - Building went further over when the DISCS arrived, and deliberately in the
    shape the fix above wants: what a disc lends a tower is a TowerBuffs object
    the tower owns, exactly as TowerStatus is, so the five methods added are
    two accessors and three readings that fold it into an answer that already
    existed. Splitting mana out the same way is still the intended fix and is
    now the only one left
- MatchSession.gd is over gdlint's public-method ceiling, and was already over
  it before the match settings arrived - it answers for the roster, the RNG,
  the clock and the unit registry, and those four are what "what is true of
  THIS match" means. The settings and the pause added four more: what the
  match agreed to, and whether the world is moving. Splitting the unit
  registry out is the obvious cut if it is ever worth making; the other three
  belong together
- OrderOverlay rebuilds a unit's markers WHOLE on every change to its chain,
  so shift-queueing five towers instantiates the ghost models five times over
  in one frame - each rebuild frees the last, but queue_free is deferred, so
  they briefly coexist. Harmless and invisible; the fix if it ever matters is
  to diff the chain rather than rebuild it, which is more code than it is worth
  while a chain is a handful of entries long
- Every disc runs a scan of its own on a quarter second beat: an aura disc
  walks the area's buildings, an on-step disc walks its creeps. Cheap next to
  the two below - it is four times a second rather than twenty, and a maze
  holds a handful of discs rather than a hundred creeps - and it wants the same
  spatial hash when one arrives
- Two naive linear scans over an area's creeps: TargetFinder and
  Creep._refresh_aura. One spatial hash fixes both. TargetFinder is by far the
  worse of them and is the largest single cost in a loaded tick - a tower with
  nothing in range rescans the whole lane every tick and finds nothing again
  - creep separation was the third, and is no longer paid: it now runs for
    ATTACKER creeps only and is skipped without a call for everything else.
    Switching it back on for the whole roster puts it straight back
- Replication sends the whole world every tick, every unit in it. Fine for a
  1v1 on a LAN, nowhere near 12 players. That is multiplayer.md
  3.3, deliberately deferred until there was something to measure
  - a unit record grew by two floats when towers gained mana, and two more
    when the Beastmaster gained an ability a player AIMS - its cooldown and
    what it is linked to, which every unit in the world now carries a slot for.
    Creep mana rides the mana fields rather than adding its own, so nothing
    grew for it
- A client is told what status effects are on the ONE unit its panel is showing
  and on no others - it asks, and the server answers in the snapshot. So the
  debuff row is right, and a creep somebody is not looking at still carries
  effects the client knows nothing about. That is deliberate; the complete
  version would cost more than the rest of the snapshot put together
  - WHAT rides that channel is `Unit.status_entries()`, which is virtual, and
    it has to stay that way. It used to be a cast to Creep in the two places
    that asked, and that cast silently kept THREE whole systems off the wire:
    what a technology disc lends a tower, what a creep curses one with
    (TowerStatus), and the armour a creep's packmate aura grants it. All three
    were real on the server and invisible to both clients, so a client drew a
    tower standing in a Primal disc at its own range - the wrong circle around
    a tower that really did have the reach. Anything that grows a fourth kind
    of effect overrides that method and is replicated for free; a cast added
    back anywhere on this path silently un-fixes the lot
  - and WHO folds it in is the unit, never the reader. `armor_value()`,
    `attack_speed_ratio()`, `attack_damage_ratio()` and `attack_range_bonus()`
    each answer from the objects on the authority and from the replicated
    entries on a client, so the panel, the range overlay and the barrels cannot
    disagree. The panel used to carry that branch itself, which worked only
    because it was the only reader - three more arrived with the discs
- Godot's gl_compatibility renderer, which this project uses, silently drops
  two things that look like clean one-liners: PER-INSTANCE SHADER UNIFORMS and
  GeometryInstance3D.transparency. Neither errors, both simply do nothing. That
  is why a tower's tier is baked into one material per tier rather than
  overridden per tower, and why an effect's opacity duplicates its materials
- The editor does NOT reload a script whose BASE CLASS changed. Its property
  disappears from the inspector and a filesystem scan does not help - only
  restarting the editor does. Different from the stale-signature trap below,
  and headless is the honest answer in both cases
- Two traps not covered by the rules above: SelectionController._select_in_rect
  must FALL THROUGH when the box caught neither a commandable unit nor a creep,
  or an empty box stops clearing the selection; and AttackRangeOverlay.MAX_CIRCLES
  must match the const in Resources/Shaders/attack_range.gdshader
- An upgrade chain is a CHAIN OF ext_resources: a tower's stats name the upgrade
  ability above them, which names the next tower's stats, all the way to the
  Ultimate. So loading the 10g tower of a line pulls that whole line into
  memory, and one broken .tres in the middle takes every tower BELOW it down
  with it - the load-time dependency trap the PackedScene rule already warns
  about, reached the long way round. It is why prefabs and models are still
  named by PATH from those files, which is what keeps the blast radius to the
  stats and not the scenes. Main._validate_content walks the chain at boot

# Look & setting
- Broadly to be decided. **Only placeholder visuals are wanted, and the visual
  rules that exist were authored by Claude rather than handed down** - so
  unlike everything else in this file, none of them is binding
  - they are there for CONTINUITY: a roster added later should look like it
    came from the same game as the ones before it, and rules are the only way
    that survives thirty units nobody can hold in their head at once
  - so CHANGE ONE WHEN IT IS WRONG, and change it in Tools/ModelGen/style.py
    rather than in a generated file, so the whole roster moves together. What
    it costs is the continuity it was buying, which is worth weighing and is
    not a prohibition. PLACEHOLDER_ART.md section 0 is the long version
  - two have already moved, which is what that looks like in practice: "a
    flyer is translucent" retired when the first solid flyer arrived, and "a
    creep's only lit parts are its eyes" gained a named exception for a
    burning Boss
- The written-down language, as it stands: the TOWER roster answers three
  questions on three axes - shape and material say which LINE, one silhouette
  change says which BRANCH, and six cumulative rules on the price tier say
  which TIER. Basic towers carry no colour of their own, because the ten
  elements each need one. Under Presentation in game_rules.md
- Everything else - setting, period, palette beyond that constraint, whether
  any of this is grounded or fantastical - is still open
