# Line Tower Wars - Game Rules

**This file holds the RULES: how the game works. It does not hold numbers.**
Every cost, stat, roster entry and balance value lives in `unit_data.md`, which
records the Warcraft III Line Tower Wars 12.4a design this prototype copies. Where
this file needs a number to explain a rule, it points there rather than repeating
it - a number written twice diverges the first time one copy is edited.

So: what happens when a creep reaches the end of a maze is here. What that creep
costs is in `unit_data.md`. Once a unit is implemented its `.tres` is the authority
over both.

Status: living document. Expanded incrementally as features are implemented.
A rule marked NOT BUILT is decided but has no code behind it yet. Everything else
described here is implemented and working. Values marked TBD are not decided yet.

# Core concept
- PvP tower defence for 2-12 players
- Each player owns one area and defends it alone
- Creeps are sent by players, never spawned by the game
- Sending creeps raises your permanent income
- The core of the game is the balance between investing in offence (sending) and defence (towers)
- No team modes. Always free for all

# Send topology
- Players are arranged in a fixed ring
- Every player sends creeps to their right neighbor and receives from their left neighbor
- Example with 5 players: 1 sends to 2, 2 to 3, 3 to 4, 4 to 5, 5 to 1
- On elimination the ring closes by skipping the dead player
  - If 5 dies, 4 now sends to 1
- In a 1v1 both roles are the same player: you send to and defend against your only opponent
- This defines send/receive order only. Physical placement of areas on the map is TBD

# Player areas
- Every player has their own separate area
- The builder can only walk and build inside its owner's area
- Other players' areas can be viewed on the minimap to inspect their maze
- Later: attacker creeps can be actively controlled inside enemy areas

# Map layout
- The map is a fixed grid of 12 area slots, 6 across and 2 down, copying the
  Warcraft III map
- Slots fill left to right and then row by row, so player 1 is the top left one
- Both rows run the same way round: every lane spawns at its own top and ends at
  its own bottom
- The map is the same size whoever turned up. A 1v1 uses two slots and the other
  ten are empty ground; the camera and the minimap still cover all twelve
- Everything that is not a player area is black

# The builder
- Each player controls one builder unit
- The builder places all towers - building is a physical action, not a menu click
- Placement works like the WC3 undead faction: the builder only has to be in range to start the tower
  - The builder does not actively construct it and is free immediately
  - The tower builds and finishes itself
- Build time is short, currently 2 seconds per tower
- Invulnerable: cannot be damaged or killed
  - It therefore never shows a worldspace health bar, unlike other units
- No collision: passes through towers and creeps
  - It still cannot leave its own area
- NOT BUILT: can attack creeps
  - Typically only relevant in the early game against weak creeps
- Stats live in a per-unit resource: health, damage range, armour type, movement speed
  - Current builder values are placeholders and not balanced
- TBD (much later): full control scheme, chained actions

# Presentation
- Gameplay is top down and effectively 2D, played on the xz plane
- Visuals are 3D, as in most RTS games
- Placeholder art is simple primitive shapes until real art exists

# Controls
- Mouse controls follow the WC3 standard
  - Left click selects a unit, or gives an attack order when the click lands
    on a creep and the selection can shoot it
  - Left click and drag draws a selection box
  - Right click on walkable ground issues a move order to the selection
- A multi selection only ever holds one unit type, from one owner
  - A selection box drawn across a mixture keeps the first unit's type
  - A box that catches both units and buildings keeps the units
- Anything can be clicked to inspect it, including creeps and enemy units
  - It fills the normal unit panel; a unit that takes no orders simply shows an
    empty command card, or just its passives
  - A selection box prefers what the player can COMMAND. Only when a box catches
    nothing of the player's own does it fall back to what is merely selectable
  - That fallback comes back with exactly ONE unit, the one nearest the middle
    of the box, and mobile units beat structures the same way they do elsewhere
  - So dragging across your maze still hands you the builder standing in it
    rather than the pack walking past, and dragging over the pack alone hands
    you a single creep to read
  - One at a time, because a creep takes no orders and a panel describing a
    crowd of them would have nothing to say. Own commandable creeps, once
    attacker creeps exist, are picked up by the normal rule instead
  - A box that catches nothing at all still clears the selection
- Holding shift while selecting adds to the current selection instead of
  replacing it, by click or by box
  - Shift clicking an already selected unit removes it again
  - Only units matching the selection's type can be added, by the rule above
  - Shift clicking empty ground keeps the selection rather than clearing it
- Double clicking a unit selects every unit of exactly that type
  - Exact type, not category: double clicking a Basic Tower picks up Basic Towers
    only, never other tower types, and later never other upgrade levels
  - Own units only, so an enemy's identical towers are never caught
  - The window is 0.5 seconds for now
- Control groups on the number keys 1 to 9
  - Control plus a number assigns the current selection to that number
  - The number alone recalls that group
  - The same number twice inside the double click window also centres the camera
    on the group's first unit
  - Units that die or are sold drop out of every group they were in
- A unit can never be ordered out of its owner's area
  - An order aimed outside it walks the unit as close as it can get, as in WC3,
    rather than being dropped
- Holding an ability's hotkey repeats it, ramping up to a capped rate
  - Opt-in per ability, so leaning on a key can never repeat Sell or Cancel
- Ability hotkeys are a GRID, WC3 grid style: the key an ability answers to is
  decided by WHERE IT SITS on the command card, never by its name
  - Top row q w e r, middle row a s d f, bottom row y x c v
  - So one square is always one key, whatever unit happens to be selected
  - An ability names the SQUARE it claims rather than a key. Anything claiming
    no square falls into the first free one
  - Sell and both Cancels sit bottom right, so the destructive key is in the
    same place on every card and never moves
  - An empty square leaves its key alone, so the rest of the game's keys keep
    working while a unit is selected
  - Passives draw no letter and cannot be pressed
  - The bottom row is y x c v because the keyboard is German. An American
    layout wants z x c v, which belongs in a settings menu once one exists
  - The letters live in Resources/Config/controls_config.tres, one string per
    row, so relaying the card out never means editing an ability
- TBD: chained actions, controller scheme
# Interface
- A unit panel sits at the bottom of the screen while exactly one unit is selected
  - Unit portrait on the left with current and max health below it
  - Unit name, damage with its damage type, and armour with its type in the middle
    - The damage line is left out entirely for anything that cannot attack, so a
      creep's panel carries no line that only ever says "not this one"
  - Below those, attack speed and range, on a line that is left out entirely
    for anything that cannot attack
  - A command card grid on the right holds that unit's available commands
    - 4 squares across by 3 down. Most units leave most of it empty, which is
      the price of the send building and the build menu having room
  - A slot carries its ability's hotkey letter small in the top left corner,
    leaving the middle of the slot to the icon once icons exist
  - A command slot shows a count in the bottom right corner where the ability
    has one, e.g. the sends left in a creep's stock
  - When there is none left, the slot is covered by a radial cooldown sweep
    that unwinds as the next one comes back
- Hovering a command slot describes it, after a short delay
  - Name and hotkey, then what one use costs, then what it gives, then the
    stats of what it produces, then that unit's passive abilities
  - Any block the ability has nothing for is left out, so Move is two lines
    while a creep send fills the whole card
  - A send describes the CREEP rather than the send, and reads every number off
    that creep's own stats, so the card cannot quote a price it does not charge
  - Its blocks are: name and hotkey; gold cost of one send and the population
    one creep takes; income gained; health, armour, speed and bounty as a 2 x 2
    grid; then the creep's passives
  - Pack size is deliberately not shown, so a player cannot currently read how
    many creeps one send buys. Open question
- Gold sits in the top right, with income and the countdown to the next payout
- Across the TOP MIDDLE: gold, living population against the cap, and the
  countdown to the next income payout
- Top right, a table of every player: name, life, income, value and placement
  - Value is the gold standing on the field: every building they own at what it
    cost. Later it also carries upgrades and researched technology
  - Placement is blank until that player is out, when it becomes their finish
  - Large numbers are shortened: 999, then 1.2k / 15.6k, then 102k / 903k, then
    1.2M
  - TBD: the NAME. An anonymous mode showing the player's COLOUR instead belongs
    to a game mode selection that does not exist yet, and player colours are not
    built either, so it is the display name for now
- The minimap sits in the bottom left corner, square, and shows the whole map
  - A lane is drawn as its spawn strip and its buildable body. The send strip
    above them is left out: nobody plays on it
  - Everything standing on the map is a square - one size for every building,
    a smaller one for every mobile unit. A maze's SHAPE is deliberately not
    readable at that scale, only roughly where its towers stand
  - Colour says ownership and nothing else. A creep carries its SENDER's
    colour, so an opponent's creeps in your own maze read as theirs
  - Three schemes exist, and which one is used is a setting:
    - yours white, everyone else's red. The default
    - yours white, everyone else's in their own player colour
    - everyone in their own player colour, yours included
  - NOT BUILT: any way to change that setting in game. There is no options
    menu yet, so it is set in the presentation config
  - NOT BUILT: player colours are not chosen in the lobby yet, so the two
    schemes that use them fall back to a fixed list indexed by slot
  - A rectangle shows where the camera is looking. The camera's real footprint
    is a trapezoid, since it looks down at an angle, but the box is drawn square
    off the near edge of the view and always stays whole inside the minimap
  - Left clicking jumps the camera there, and holding keeps steering it
  - TBD: giving orders from the minimap
- A move order marks the clicked ground position with a short lived marker
  - Four arrows converge on the spot and fade, the usual RTS click feedback
  - It marks where the player clicked, not where the unit ends up
- Selecting several units at once switches the panel to a group layout
  - The health readout comes from the first unit selected
  - The name and stat lines are replaced by a grid picturing every selected unit
  - Clicking one of those tiles narrows the selection to that unit alone
  - The command card shows only the abilities every selected unit shares
  - Selecting more units than the grid pictures is allowed. The extra ones are
    simply not shown, and stay selected

# Camera
- The camera never follows the builder automatically
- Controlled by the player only
  - Holding the mouse wheel and dragging
  - Arrow keys
  - Edge panning, currently switched off in the camera config
  - WASD is deliberately not used for the camera, it is reserved for builder hotkeys
- A center-on-target function exists to snap the camera to the builder or any other unit or building
  - Reached by tapping a control group's number twice
- Panning is bounded to the whole map, plus the send strip above the top row so
  the send building can be reached. The bound is the MAP rather than the areas
  in play, so the empty slots of a small match can still be panned over
- No zoom for now
- TBD: controller equivalent of edge panning

# Grid and building area
- Lane direction is top to bottom
- The walkable space is 8 wide and 34 long in player cells, made of three stacked zones
  - 8 x 3 at the top: creep spawn zone, not buildable
  - 8 x 30 in the middle: the building area, the only buildable zone
  - 8 x 1 at the bottom: the end zone creeps walk to, not buildable
- Above all of that sits a further strip holding the send building
  - Not walkable, not part of the grid, and not reachable by any unit
- Both the builder and creeps can walk the full 8 x 34
- Internally every player cell is 2 x 2 internal cells
  - Building area is 16 x 60 internal, full walkable space is 16 x 68 internal
  - This exists so half-cell positions are whole numbers internally
  - Only the player-facing cell view is shown to the player
- Towers are always 1 player cell (2 x 2 internal)
- Towers can be placed on full or half cell positions, e.g. 4.5 | 15.0
- A tower blocks its entire footprint for walking
- Creeps need at least 1 free internal cell to walk through
- The grid is toggled by a BUILDER ABILITY in card slot 9, so the key follows
  the slot like every other ability rather than being a binding of its own
  - It covers EVERY maze at once, not just your own: where a tower can go is
    worth reading in an opponent's lane too, and half the board in a different
    state would be a second thing to keep track of
  - Local only: it changes what one player sees, never travels to the server
  - X is no longer available: it is the bottom middle square of the command card
  - Only player cells are drawn, internal half cells are never shown
- Grid coordinates are labelled in the border outside the buildable area, for orientation
  - Row numbers 1 to 30 run down the left side, 1 at the top
  - Labels are only visible while the grid is visible
  - TBD: column labels along the bottom

# Mazing
- Players place towers to lengthen the creep path
- A creep path from entrance to exit must always exist
  - Placement that would fully block the area is forbidden and rejected before the tower is built
  - This is a deliberate deviation from the WC3 original, where blocking caused creeps to attack towers
- Towers can be built at any time, including while creeps are in the maze
- Creeps never block tower placement
  - A tower built on a creep's position sets that creep back along the route it
    has already walked, to the most recent point still clear of the tower
  - Deliberately not the nearest free space: nearest is often on the far side of
    the very wall the creep was walking around, which would turn building a
    tower into a shortcut for the creep standing there
  - A tower built into a creep's route does not redirect it straight away. The
    creep walks up to the tower and only then takes a new route
- Path recalculation was a known performance concern, settled by giving each area
  one shared route rather than pathing every creep separately

# Towers and attacking
- A tower attacks by itself, and can also be ORDERED onto one specific creep
  - The order is an ability on the card, and also a plain click on a creep -
    either button - whenever the selection holds anything that can shoot it
  - A creep clicked while nothing that can attack is selected still just
    selects, so reading a creep never stops working
  - Arming the ability draws the reach of every selected unit on the ground, as
    ONE shape rather than a circle each: overlapping ranges are painted once,
    so two towers covering the same ground never darken it. Each tower's own
    outline is still drawn inside the union, so it stays clear which tower
    reaches where
  - Left click on a creep gives the order, right click or Escape cancels, and a
    left click on anything else cancels without ordering
  - A tower out of range REFUSES the order quietly and carries on with whatever
    it was already shooting, rather than standing idle. That is what makes the
    order safe to give to a whole selection: the towers that can help switch,
    the rest are untouched
  - A commanded target is an ordinary target afterwards. It is dropped when it
    dies or leaves range, and the tower goes back to picking its own
  - Ordering never turns the automatic behaviour off. It only overrides which
    creep is current
- An attack order is confirmed on the TARGET, not on the ground
  - A red ring blinks on the creep for about a second and a half, then goes
  - It rides the creep and dies with it, so it can never point at a corpse
  - The move order marker is deliberately NOT shown for an attack: what was
    chosen is the creep, and a marker on the floor would answer a different
    question
- While any ability is waiting for its target, the command card empties
  - Nothing else can be pressed or hotkeyed until the order resolves or is
    cancelled. The grid keeps its place, so the panel never changes shape
  - Applies to Move, to Attack and to placing a tower alike
- One attack per tower, described by that tower's own attack stats
  - Attack speed in attacks per second, written as APS in the UI, so a bigger
    number is faster
    - `unit_data.md` states the same value the way the source game does, as the
      COOLDOWN IN SECONDS between attacks, where a bigger number is slower. The
      two are reciprocals; do not copy one into the other without inverting it
  - Range in player cells, measured from the tower's centre to the creep's
  - Damage as a min to max range, rolled fresh per attack, plus a damage type
  - Whether it can hit ground targets, air targets or both
- A tower attacks every creep walking its own area, whoever sent it
  - Deliberately not an enemy test: creeps belong to the sender, so a hostility
    check would have a player's towers ignore exactly what they are defending
    against
- A tower picks one target and keeps it until it dies or leaves range
  - Default priority is the creep furthest along its route, the classic tower
    defence "first in line"
  - Measured along the route that creep actually committed to, so one that took
    the long way round counts as being where it really is
  - Other priorities exist in the data - closest, strongest, weakest - and no
    tower uses them yet
- A tower still going up cannot attack. One being sold still can, since the
  sale can be called off and it is still standing
- How the hit reaches the target is one of two kinds, never both
  - Instant: the damage lands the same moment the tower attacks, with or
    without a visual. A tower can be a spinning blade that simply hurts what
    stands next to it
  - Projectile: a projectile is spawned, flies to the target and deals its
    damage on impact. It carries its own speed and flight arc
  - A projectile homes, so a creep cannot outwalk a shot already aimed at it
  - A target that dies mid flight does not waste the shot: it lands where that
    creep last stood, so a splash still catches the crowd around it
  - Selling a tower never deletes a shot already in the air
- What happens on impact is a list, so one attack can do several things
  - Splash damages everything within a radius of the point that was hit, minus
    the creep that was hit, which already took the attack's own damage
  - Splash is measured from the impact, not from the tower, so it reaches
    creeps the tower itself could not have shot
  - Chain and status effects such as slows and damage over time are the same
    shape and are NOT BUILT
- NOT BUILT: multishot
  - Multishot picks one primary target and then that many further creeps
    standing near it, so multishot 2 attacks 3 creeps in total
  - "Near" is one distance shared by the whole game, not a per tower value
  - A projectile attack fires one projectile per target

# Towers - which ones exist
The roster, the upgrade chains, the names and every number are in `unit_data.md`:
basic towers in its section 3, elemental towers in section 4, the naming scheme
in 2.4, and the technology that gates the elemental ones in section 2.

The rules that hold whatever the roster says:

- Basic towers are available from the start and need no research
- Elemental towers require technology, which is a later feature and NOT BUILT
- A tower is upgraded rather than replaced: an upgrade chain carries one name and
  a tier prefix, so a player follows one line rather than relearning it each tier
- Towers do not look like living creatures. That is a setting constraint on art,
  not a balance one, and it survives any renaming

**The four towers currently implemented - Sniper, Cannon, Meatgrinder and Stomper -
are a TEST SET and are all being replaced** by the real roster from `unit_data.md`.
Their names, costs and stats were placeholders chosen to have something to shoot
with, and none of them was balanced. Nothing should be built on top of them.

# Damage and armour
Two separate questions decide what a hit costs, and they are kept deliberately
apart: armour TYPE, which is a matchup, and armour POINTS, which is a number.

- Every attack carries a damage type, every damageable unit an armour type
- The pair decides what share of the attack's damage actually lands
- **The matrix itself is in `unit_data.md` section 1.1**, and is stored as
  `Resources/Config/damage_table.tres`, which is the authority
- Chaos reading 100% against everything is a balancing value like any other, not
  a rule, so nothing may shortcut it as "ignores armour"
- Invulnerable is not a row. It is the absence of damage, not a resistance to it
- Magic is a PHYSICAL damage type and goes through the table like any other. The
  damage that ignores the table entirely is SPELL DAMAGE, which is not a row in
  it: it ignores armour type and armour points both, and is resisted only by
  explicit creep traits. Nearly every tower ABILITY deals it; no tower's basic
  attack does

- Armour POINTS are a separate number every unit carries, independent of armour
  type. Who has how many is `unit_data.md`
  - Positive armour reduces damage with diminishing returns, so armour can
    never reach immunity however much of it is stacked:
      reduction = (armor * 0.06) / (1 + 0.06 * armor)
  - Negative armour amplifies damage instead, and never quite doubles it:
      amplification = 2 - 0.94 ^ -armor
  - Both read exactly 100% at 0 armour, which is where the two halves meet
  - The two constants live in `damage_table.tres` beside the matrix
- Some attacks are AREA damage, which some creeps resist. A flag on the attack,
  covering the primary hit as well as the splash around it
  - Any splash counts as area damage whatever its attack says, since covering
    ground is what a splash is
  - Multishot is deliberately NOT area damage: it picks several single targets
    rather than covering ground
- A hit resolves in a fixed order, and that order is a rule rather than an
  accident of how anything happens to be listed:
    1. roll the attack's damage
    2. the damage type versus armour type matrix
    3. the target's own resistances, such as a trait halving area damage
    4. the target's armour points
    5. any flat block, such as Hardened Skin
  - Percentages resolve before flat points on purpose. A flat block is meant to
    blunt many small hits rather than one big one, and putting it last is what
    makes that true
- Damage is rounded to whole points, and an attack that lands at all does at
  least 1. So a block can blunt a hit but never swallow it entirely
- Towers and buildings currently all carry Unarmored, which is a placeholder
  standing in until the real roster is authored, not a balancing decision

# Creeps
- Creeps enter at the top and walk to the bottom
- Spawn position is randomised: random x across the width, random y within a margin at the very top
  - Every creep of a pack rolls its own position, so a pack arrives spread out
- Creeps carry a worldspace health bar like any damageable unit
- Creeps take no orders from anyone
  - They can be clicked to inspect, showing the normal unit panel with an empty
    command card, but never selected by a selection box and never commanded
  - Attacker creeps will be the exception once they exist
- Creeps belong to the player who sent them, not to the player whose maze they
  are walking. That is who the life steal will pay
- Pathfinding
  - Each area keeps one route to its end zone, rebuilt whenever a building goes
    up or comes down
  - A creep takes a route once and then commits to it. It keeps walking the
    route it set out on however much the maze changes around it
  - It only re-routes at the moment it arrives at the first tower actually
    standing in that route, and it re-routes from there, at the tower's face
  - So building behind a creep never redirects it, a tower dropped further along
    its route does nothing until the creep reaches it, and selling a tower never
    pulls a creep off the longer way it was already committed to
  - Creeps cut corners diagonally but never squeeze between two towers that only
    touch at a corner, matching the rule that they need a whole free internal cell
  - Creeps push each other apart softly, so a pack crowds at a choke point
    rather than stacking into one body
- Killed creeps pay bounty gold to the player whose maze they died in
  - Not to whoever fired the killing shot and not to the sender, so nothing
    anywhere has to track who dealt the damage
  - Each creep type carries its own bounty, see the roster
  - A creep that reaches the end zone pays nobody. Only a kill does
- Reaching the end zone steals a life and recycles the creep instead of removing
  it, see the Lives section
- NOT BUILT: flyers, attackers and bosses
  - Attacker creeps can attack buildings and are the only actively controllable
    creep type
  - An attacker creep can only ever target a TOWER. The builder and technology
    discs cannot be attacked at all - not "are tough", not "are ignored while a
    tower is in range": they are not valid targets, ever. A maze wall made of
    discs is a wall an attacker cannot chew through, and that is deliberate.
    See unit_data.md
- TBD: unlock order

# The creep roster
**The roster is `unit_data.md` section 6**: which creeps exist, what they cost,
what they are worth in income and bounty, their health, armour, speed, pack size
and traits, sorted into four tiers. The trait glossary is 6.6.

The rules that hold whatever the roster says:

- A tier is a COST BRACKET and carries no mechanical meaning. A creep is not
  stronger or differently targetable for being in one, and a lower tier is never
  retired by a higher one - Sudden Death is the single exception
- Creeps unlock one at a time on the match clock, each by its own start delay,
  never as a whole tier at once. Sudden Death is again the exception
- Bounty is per creep, so a pack pays out once per creep in it
- Income is per SEND rather than per creep, and the ratio of income to cost gets
  worse as creeps get stronger. That is what makes early sends compound
- Population is charged per creep, not per send
- Auras: EVERY creep aura shares ONE radius, so a player learns the size of an
  aura once and it holds for all of them
  - Stored on `GameConfig`, never per creep
  - Auras do not stack: the best one in range applies, never the sum
- A creep that revives rather than dying does not pay bounty and keeps the route
  it was already committed to. Killing it again pays as normal
  - A revive waits before it happens, and is visible while it waits. A creep that
    popped straight back at a fraction of its health was killed again by the very
    next shot, so nothing a player could see ever happened - and the wait is also
    what gives the maze a real window, since the tower that was shooting it moves
    on to the next creep
  - While down it is hidden, does not move, is shot at by nothing, grants and
    receives no auras, is walked straight through and cannot be clicked

**The six creeps currently implemented - Sheep, Skeleton, Acolyte, Spider, Knight
and Grunt - are a TEST SET and are all being replaced** by the real roster. Their
costs, stats and passives were placeholders chosen to have something to send, and
none of them was balanced. Some names survive into the real roster by coincidence;
the numbers behind them do not.

# Sending creeps
- Creeps are purchased in a dedicated building located above the player's own building area
  - It stands on its own strip above the walkable space, outside the grid, so it
    never blocks a path and can never be built on
  - It is invulnerable and permanent: it cannot be sold, damaged or destroyed
  - It is an ordinary unit otherwise, so it can be selected and control grouped,
    and its command card is the list of creeps it can send
- A send is priced as a whole pack, not per creep
  - One press costs the creep type's gold cost, spawns its pack and grants its
    income once
- A player sends into their RIGHT NEIGHBOUR's area, resolved through the ring on
  every send so an elimination closing the ring needs nothing invalidated
  - A one-player run has no neighbour, so it falls back to sending into your own
    area - which is what keeps solo testing working
- NOT BUILT: creeps unlock over game time, each on its own start delay. Until
  that exists every implemented creep is sendable from the first second
  - The delays are per creep and are in `unit_data.md` section 6
  - It also removes the need for a separate rule disabling sending at the start:
    nothing is unlocked yet, so there is nothing to send
- Normal creeps are sent in packs, bosses as a single larger creep. Pack size is
  per creep type and is in the roster
- Each creep type has its own stock of sends, so one type cannot be sent
  infinitely. Maximum stock and replenish rate are per creep type
  - The replenish timer only runs while the stock is below full, so waiting at
    full never banks an instant refill
  - A creep's own trait can speed its reserve up. It scales the base rate rather
    than replacing it, so the base rate stays the one number everything is
    measured against
  - A send costs one stock. At zero the creep cannot be sent at all
  - TBD: starting stock. The prototype starts full so the opening burst is
    available; `unit_data.md` records the source game as starting at half
- Holding a creep's hotkey repeats the send, accelerating up to a capped rate,
  which is how a full stock gets dumped quickly
- Population is charged per CREEP, not per send, and is counted per SENDER
  wherever those creeps happen to be walking
  - SHOWN but NOT ENFORCED: the status bar draws the count against the cap, and
    nothing yet refuses a send that would exceed it
  - At the cap no further creeps can be sent
  - Each creep type carries its own population value; the exceptions are in the
    roster

# Economy
- Gold is spent on towers and on sending creeps
- Income is paid out on a fixed interval
  - One shared clock, so every player is paid on the same beat
- Starting gold and starting income are match rules, and live in
  `Resources/Config/game_config.tres`
- Sending a creep permanently increases the sender's income
  - The raise applies from the next tick onwards, never retroactively, so
    sending just before a tick is worth no more than sending just after one
- Income therefore compounds: early sends outscale late sends
- Every creep has an implicit income ratio of cost to income granted, and the
  ratio gets worse as creeps get stronger. Special creeps such as attackers are
  worse still, and some Tier 4 creeps grant no income at all
- There is an income CAP, above which Tier 4 income gain is heavily reduced
- Killing creeps in your own area pays bounty gold, see Creeps
- Every one of these numbers - send cost, income, bounty, the cap - is in
  `unit_data.md`, sections 1.7 and 6

# Life steal and recycling
BUILT.

- Lives are stolen, not just lost
- When a creep reaches the end of a maze, its owner steals 1 life from the defending player
  - The defender loses 1 life and the owner gains 1
- The creep is not removed. It is teleported to the next player's maze and continues
  - Current HP is carried over unchanged
  - This is called recycling
- Example: player 1's creep leaks player 2, so the creep moves on to player 3
  - In a 1v1 it returns to player 2
  - Generalised as "advance to the next living player in ring order, skipping the
    creep's owner", which is what is implemented
  - When there is no such player - a single area, or a 1v1 whose other player is
    out - there is nowhere to advance to and the creep leaves instead of looping
    in one lane forever
- A player with no lives left is eliminated. Nothing acts on that yet beyond the
  ring skipping them, because the win condition below is deliberately not built
- Starting lives depend on the player count: fewer players means more lives each
  - The prototype derives them from a formula so any player count works, kept in
    `Resources/Config/game_config.tres`
  - The SOURCE GAME instead sets them per player count and per ruleset, and those
    figures are in `unit_data.md` section 1.7. Adopting them is pending a ruleset
    concept, which does not exist yet
- Bosses steal more than one life. How many is per creep, in the roster

# Win condition
BUILT, in the smallest form: the match decides itself and then stops. There is no
end screen yet - players leave through the in-game menu.

- Last player standing
- A player at 0 lives is eliminated: EVERYTHING of theirs leaves the field and
  they are given a final placement
  - Their towers, their builder, their send building, and the creeps they have
    sent - wherever those are still walking
  - Removed, not killed: no death passive fires, so a Skeleton does not get back
    up, and no bounty is paid to whoever's lane a creep happened to be in
  - Placement counts DOWN from the number still playing, so the first player out
    of five takes 5th and the survivor takes 1st
- Once one player is left the match is over: the income timer stops where it is
  and nobody can send any more
- Simultaneous elimination does not exist
- If two life steals would resolve on the same frame, the one that triggers first wins
  - Resolution is by execution order and is deterministic. Eliminations are
    settled in ascending slot order, which is that order

# Values Claude chose that you have never reviewed
Recorded because they LOOK decided and are not. None is a rule; all are choices
made to get something working, waiting on your word.

**No current values are listed here on purpose.** A number written down here goes
stale the moment the `.tres` behind it is edited, and this file is never the one
that gets edited with it. What is recorded is WHICH decision was never yours.

- Every tower and creep currently implemented is a placeholder set being replaced
  wholesale from `unit_data.md`. Their costs, stats, armour types and names were
  all chosen by Claude and none was balanced. The attacks-per-second values are
  the exception - those are yours
- Towers and buildings carry Unarmored and no armour points, which is a stand-in
  rather than a decision
- The Sniper's projectile arc is a guess: "rather straight curve" was read as
  mostly straight rather than flat
- Passive names on the test creeps echo the WC3 originals. Strings only, and they
  go with the test set
- The send building's display name is still a placeholder
- Creep and tower models are primitives varying only by shape, size and colour
- Creep separation strength is a tuning value you change while testing. Whatever
  it currently reads is a test state, not a decision - and the waypoint bug it was
  once masking is gone, so it is worth a real call at some point
- Starting gold in `game_config.tres` is set far above its script default as a
  deliberate test value, so building is quick to try

# Open questions
- Recycling rule generalisation for 3+ players (deferred)
- Map layout for more than 2 players (deferred)
- Whether the send tooltip should state pack size
- Whether to copy the source game's FOUR send buildings, one per creep tier, or
  reach the tiers from one building some other way. A UI question, not a rules
  one - nothing about a creep changes either way. See `unit_data.md` 6.1
- Whether to adopt the source game's per-ruleset starting lives, which needs a
  ruleset concept first. See Life steal
