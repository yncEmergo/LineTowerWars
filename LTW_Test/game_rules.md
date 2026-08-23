# Line Tower Wars - Game Rules

Status: living document. Expanded incrementally as features are implemented.
Values marked TBD are not decided yet. Values given are current, not final.

A rule marked NOT BUILT is decided but has no code behind it yet. Everything
else described here is implemented and working.

# Core concept
- PvP tower defence for 2-15 players
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
  - A minimap is required, to be added later
- Later: attacker creeps can be actively controlled inside enemy areas

# Map layout
- Player areas are placed side by side along the x axis
- For the 1v1 prototype: player 1 on the left, player 2 on the right
- TBD: layout for more than 2 players

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
  under it
- Space is left free at the bottom left of the screen for the minimap
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
- Panning is bounded to the span of every player area, plus the send strip above
  them so the send building can be reached
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

# The basic towers
Basic towers are available from the start. Elemental towers need research and
are a later feature. Every basic tower's base version costs 10 gold.

All four names and all of their numbers are placeholders and are not balanced.

- Sniper Tower: single target projectile, long range, fast, low damage per hit,
  piercing
- Cannon Tower: single projectile that splashes everything around whatever it
  hits, medium range, slow, medium damage, siege. AREA damage
- Meatgrinder Tower: a blade that spins in place and hits a single target at
  very close range, very fast, high damage, normal. No splash. NAME TBD
- Stomper Tower: very close range like the meatgrinder, but a huge splash of at
  least 2 x 2 player cells, very slow, high damage, normal. AREA damage. NAME
  AND CONCEPT TBD, other than that towers are not to look like living creatures

# Damage and armour
Two separate questions decide what a hit costs, and they are kept deliberately
apart: armour TYPE, which is a matchup, and armour POINTS, which is a number.

- Every attack carries a damage type, every damageable unit an armour type
- The pair decides what share of the attack's damage actually lands
- Chaos currently reads 100% against every armour type. That is a balancing
  value like any other, not a rule, so nothing may shortcut it as "ignores
  armour"
- Invulnerable is not a row. It is the absence of damage, not a resistance to it

| Armour \ Damage | Magic | Chaos | Normal | Piercing | Siege |
| --------------- | ----- | ----- | ------ | -------- | ----- |
| Light           | 125%  | 100%  | 80%    | 150%     | 100%  |
| Medium          | 80%   | 100%  | 150%   | 100%     | 80%   |
| Heavy           | 150%  | 100%  | 100%   | 80%      | 80%   |
| Fortified       | 66%   | 100%  | 80%    | 66%      | 150%  |
| Hero            | 66%   | 100%  | 80%    | 66%      | 80%   |
| Unarmored       | 100%  | 100%  | 100%   | 125%     | 125%  |

- Armour POINTS are a separate number every unit carries, and are 0 on
  everything so far. The knight's aura is currently the only source of any
  - Positive armour reduces damage with diminishing returns, so armour can
    never reach immunity however much of it is stacked:
      reduction = (armor * 0.06) / (1 + 0.06 * armor)
  - Negative armour amplifies damage instead, and never quite doubles it:
      amplification = 2 - 0.94 ^ -armor
  - Both read exactly 100% at 0 armour, which is where the two halves meet
  - Worked values: 1 point 5.7%, 3 points 15.3%, 5 points 23.1%, 10 points 37.5%
- Some attacks are AREA damage, which some creeps resist. A flag on the attack,
  true for the Cannon and the Stomper, covering the primary hit as well as the
  splash around it
  - Any splash counts as area damage whatever its attack says, since covering
    ground is what a splash is
  - Multishot is deliberately NOT area damage: it picks several single targets
    rather than covering ground
- A hit resolves in a fixed order, and that order is a rule rather than an
  accident of how anything happens to be listed:
    1. roll the attack's damage
    2. the damage type versus armour type matrix above
    3. the target's own resistances, e.g. the spider's half against area damage
    4. the target's armour points
    5. any flat block, e.g. the grunt's 10
  - Percentages resolve before flat points on purpose. A flat block is meant to
    blunt many small hits rather than one big one, and putting it last is what
    makes that true
- Damage is rounded to whole points, and an attack that lands at all does at
  least 1. So a block can blunt a hit but never swallow it entirely
- Stored as Resources/Config/damage_table.tres, which also holds the 0.06 and
  the 0.94 of the two armour curves
- Every tower and building still carries Unarmored, which is a placeholder
  rather than a balancing decision. Creeps have real types, see the roster

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
  - Each creep type carries its own bounty, see the roster below
  - A creep that reaches the end zone pays nobody. Only a kill does
- Reaching the end zone steals a life and recycles the creep instead of removing
  it, see the Lives section
- NOT BUILT: flyers, attackers and bosses
  - Attacker creeps can attack buildings and are the only actively controllable
    creep type
- TBD: unlock order

# The creep roster
Six creeps. All are sent in packs of 3, all are worth 1 population, and all
hold a stock of 32 that refills one every 3 seconds. Health runs at roughly
0.8 per gold of cost, with the sheep as the deliberate exception.

Every number here is current, not final.

| Creep    | Cost | Health | Bounty | Income | Armour    | Speed |
| -------- | ---- | ------ | ------ | ------ | --------- | ----- |
| Sheep    | 10   | 10     | 1      | +2     | Unarmored | 2.0   |
| Skeleton | 25   | 20     | 2      | +4     | Light     | 2.0   |
| Acolyte  | 40   | 32     | 3      | +5     | Medium    | 2.0   |
| Spider   | 50   | 40     | 4      | +6     | Light     | 2.2   |
| Knight   | 70   | 56     | 5      | +8     | Heavy     | 2.0   |
| Grunt    | 100  | 80     | 7      | +11    | Medium    | 2.0   |

- Bounty is per creep, so a pack of three pays out three times over
- Income is per send rather than per creep. The ratio of income to cost falls
  as the creeps get stronger, which is what makes early sends compound
- Armour POINTS are 0 on every creep. The knight's aura is the only source
- Each creep has exactly one passive, except the grunt which has two
  - Sheep, Fast Producing: its reserve in the send building refills 25% faster.
    In exchange it is far frailer than its price would suggest
  - Skeleton, Undying: the first time it dies it goes DOWN rather than away,
    and gets back up 2 seconds later with 40% of its health
    - While down it is hidden, does not move, is shot at by nothing, grants and
      receives no auras, is walked straight through and cannot be clicked
    - A shaft of yellow light stands on the spot for those 2 seconds,
      brightening and widening as the revive nears, and flashes as it gets up
    - The delay is the point. A creep that popped straight back at a fraction
      of its health was killed again by the very next shot, so nothing a player
      could see ever happened. The wait also gives the maze a real window: the
      tower that was shooting it moves on to the next creep
    - A revived creep did not die, so it pays no bounty and keeps walking the
      route it was already committed to. Killing it again pays as normal
  - Acolyte, Last Rites: heals every creep within 1.5 cells for 20 as it dies.
    Its own death is not called off, so it still pays bounty and still leaves.
    The heal lands where it FELL, so walking one in the middle of a pack is
    worth more than at the back
  - Spider, Carapace: takes 50% less area damage, and moves 10% faster
  - Knight, Devotion Aura: grants +3 armour to every creep in range, itself
    included
  - Grunt, Hardened Skin and Regeneration: blocks 10 damage from every hit it
    takes, and regenerates 5 health per second. The regeneration runs all the
    time rather than only out of combat, so a maze has to out-damage it rather
    than merely interrupt it
- EVERY creep aura shares ONE radius, currently 3 cells, so a player learns the
  size of an aura once and it holds for all of them
  - Stored as GameConfig.creep_aura_radius_cells, never per creep
  - Auras do not stack: the best one in range applies, never the sum

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
- NOT BUILT: sending is disabled for the first 20 seconds
  - Can be handled organically by not unlocking any creep until then
- NOT BUILT: creeps unlock over game time
  - The weakest 2 are available from the start. All six are available from the
    start today, since nothing gates them yet
  - Every 30 seconds the next stronger creep unlocks
- Normal creeps are sent in packs of 3 of the same type
- Bosses are sent as a single larger creep
- Each creep type has its own stock of sends, so one type cannot be sent infinitely
  - Default is 32, special creeps get their own lower numbers
  - One stock regenerates every 3 seconds, and the timer only runs while the
    stock is below full, so waiting at full never banks an instant refill
  - A creep's own passive can speed its reserve up, e.g. the sheep's 25%. It
    scales the base rate rather than replacing it, so 3 seconds stays the one
    number everything is measured against
  - Players start a match with stock full, so the opening burst is available
  - A send costs one stock. At zero the creep cannot be sent at all
- Holding a creep's hotkey repeats the send, accelerating from about three a
  second up to a cap of ten, which is how a full stock gets dumped quickly
- Population cap is 100. SHOWN but NOT ENFORCED: the status bar draws the count
  against the cap, and nothing yet refuses a send that would exceed it
  - Population equals the player's currently alive sent creeps, counted per
    SENDER wherever those creeps happen to be walking
  - At the cap no further creeps can be sent
  - Each creep type carries its own population value, 1 on every creep so far
  - TBD: whether a stronger creep is ever worth more than 1

# Economy
- Gold is spent on towers and on sending creeps
- Income is paid out once every 8 seconds
  - One shared clock, so every player is paid on the same beat
- Starting gold is 20, starting income is 20
- Sending a creep permanently increases the sender's income
  - The raise applies from the next tick onwards, never retroactively, so
    sending just before a tick is worth no more than sending just after one
- Income therefore compounds: early sends outscale late sends
- Every creep has an implicit income ratio of cost to income granted
  - Illustrative: a 10 gold creep grants 2 income, a 1000 gold creep grants 100 income
  - The ratio gets worse as creeps get stronger
  - Special creeps such as attackers may have an even worse ratio
- Killing creeps in your own area pays bounty gold, see Creeps
- Send costs, income and bounty are decided for all six creeps, see the roster

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
  - Formula: max(25, round to nearest 5 of 200 / player count)
  - The pool is roughly 200 total lives, but every player has at least 25
  - Resulting values: 2 players 100, 3 players 65, 4 players 50, 5 players 40,
    6 players 35, 7 players 30, 8 players 25, 9+ players 25
  - Above 8 players the total therefore grows beyond 200
- TBD: whether stronger creeps steal more than 1 life

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
Recorded because they LOOK decided in the files and are not. None is a rule; all
are placeholders waiting on your word.

- Every tower number except attacks-per-second is an unbalanced placeholder:
  damage, range, 200 health, and a flat 10 gold for all four. The APS values are
  yours
- Towers and buildings still carry Unarmored and 0 armour points. Creeps have
  real armour types, chosen by Claude and never reviewed
- Acolyte heal radius of 1.5 cells is Claude's; you gave only the amount (20) and
  "a small aoe"
- Sniper arc_height is 0.25 rather than 0 - "rather straight curve" read as mostly
  straight rather than flat
- The Spider's "10% faster" is plain move_speed 2.2, not a passive, so its tooltip
  advertises only the AoE resistance
- Passive names echo the WC3 originals: Fast Producing, Undying, Last Rites,
  Carapace, Hardened Skin, Regeneration, Devotion Aura. Strings only
- Meatgrinder Tower needs a real name; Stomper Tower needs a name AND a concept -
  the WC3 original was a bear stomping, and you want non-living towers, so it is
  currently a piston press
- Send building display_name is still the placeholder "Send Building"
- Creep models are primitives varying only by shape, size and colour
- Creep separation is switched OFF (SEPARATION_LIMIT 0.0 in Creep.gd), your call.
  Worth revisiting now the waypoint bug it was masking is gone

# Open questions
- Recycling rule generalisation for 3+ players (deferred)
- Map layout for more than 2 players (deferred)
- Whether a creep can ever be worth more than 1 population
- Whether the send tooltip should state pack size
