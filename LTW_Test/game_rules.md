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
- Attacker creeps are actively controlled inside enemy areas

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
- Build time is short, and it is ONE figure for every tower at every tier -
  the same one an upgrade and, separately, a sale take. They live on
  GameConfig as build_seconds and sell_seconds rather than on any tower's
  own stats, so changing them changes the whole roster at once
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
- Anything still being ASSEMBLED holds its motion still - a tower going up for
  the first time, and one being rebuilt into its next tier
  - a model that spins and bobs while it is rising out of the ground reads as
    finished, which is exactly the wrong thing to say about something the
    player is waiting on
  - it covers decoration only: a turning halo, a floating core, an idling
    blade. An attack animation is not affected, because something that cannot
    attack has no attack to animate
- An effect that stands for an AREA is drawn at the area it really covered, and
  holds there long enough to be read
  - it snaps out to full size and then rests, rather than creeping outwards for
    as long as it is on screen. The expansion is the event; the rest is what
    actually shows a player a radius, and something still growing when it
    disappears never gave them a size to learn
  - so a blast ring is exactly the ground that took damage, at every tier of
    the tower that threw it. A ring that is decorative rather than measured
    teaches a player a radius that is not real, which is worse than drawing
    nothing
- A tower's own moving parts say whether it is WORKING. A grinder's blade turns
  while it has something to kill and coasts back down when it does not, rather
  than stopping dead - and it never stops between the blows of one fight, so a
  blade chewing through a pack stays at speed the whole way through
- The tower roster has a visual language, and it is a RULE rather than a
  placeholder detail: it survives the primitives being replaced by real art,
  and it is what a 3D artist should be handed along with the models
  - a tower answers three questions from a top down camera, each on its own
    axis, so none of them can be confused with another
  - WHICH LINE is shape and material. Archer is tall and thin in quarried
    stone, Cutter is squat and wide in timber and iron, Sentry is an open frame
    holding something that floats
  - BASE SHAPE is part of that and is never a default. A roster where every
    tower is a round drum on a round plinth reads as one tower at nine sizes,
    so a line picks a number of sides and keeps it: Archer is SQUARE, because a
    watchtower is a square tower and it is the only line tall enough for the
    corners to read from above; Cutter is hexagonal, chunky but still round
    enough to spin on; Sentry is round, wanting no corners around a floating
    core. The anti-air branch breaks from its own line and goes square, because
    a launch pad is not the ring it grew out of
  - NOTHING IS ONE COLOUR. Each line carries its material at three depths - a
    base, a DEEP tone for what sits low or carries weight, and a PALE one for
    what sticks out or catches light. Three depths of one material rather than
    three materials, so a tower has parts without stopping looking like one
    object. A tower built entirely out of its base tone is a lump from above
    however good its silhouette is, because its facets have nothing to catch
    against each other
  - WHICH BRANCH is one decisive silhouette at the 150g split, and it never
    changes again up that branch: a long barrel, a tilted mortar, a spinning
    blade disc, an overhead hammer, an orbiting core, a rack aimed at the sky.
    The anti-air branch points at NOTHING on the ground, which is how a player
    reads what it can and cannot shoot before buying one
  - WHICH TIER is six cumulative rules on the PRICE tier, not on the position
    in a branch, so the third rung of six reads as the third rung wherever it
    sits: the tower grows a little, its trim metal ramps iron - pale iron -
    bronze - silver - gold - white gold, its lit accent brightens and pulses
    faster, a trim collar appears from 150g, fins from 5,000g, and a slowly
    turning ring floats above an Ultimate
  - motion is reserved for the top of the ladder. It is the loudest thing a top
    down camera can show, so nothing below an Ultimate gets a moving part that
    is not its own attack
  - the rules above are enforced by a generator rather than by hand, so a tower
    cannot quietly stop obeying them. See Tools/ModelGen
- **A 10g tower and its 30g upgrade are barely the same object.** The cheap one
  is roughly half the height, has no trim metal on it at all, is built out of
  the raw deep tone, and is missing whatever part gives the line its name - the
  crossbow, the hub, the floating core. All of that arrives with the upgrade
  - it is the first upgrade any player ever buys, so it should be the one they
    can see from across the map. That is worth more than the two tiers looking
    like relatives
- **BASIC towers carry no colour of their own**: stone grey through light
  timber brown, metal trim, and a small warm accent
  - the ten ELEMENTS each own a hue, and they can only read as elements if the
    towers a player has been looking at since the first minute are not
    competing for the same signal
  - so this is a constraint on the Basic roster specifically, and the thing
    elemental towers spend
- **The ELEMENTAL roster answers the same three questions differently**, and it
  is a rule in the same way the Basic one is
  - WHICH ELEMENT is COLOUR first and a base shape second. An element is
    recognised across a map by its hue; its shape and its side count are what
    tell two similar hues apart up close, and what carry the whole signal for a
    player who cannot use the colour
  - the ten hues are chosen AGAINST EACH OTHER rather than one at a time, and
    where two would collide they are separated on a second axis: Arcane is a
    cool blue violet on worked stone where Void is a warm magenta on near-black
    hide; Ice is pale and bright where Lightning is dark gunmetal with the light
    only in its accent; Fire, Earth and Holy all have a warm accent and are told
    apart by the VALUE of their stone - near-black basalt, mid brown, bright
    ivory
  - WHICH PATH is one decisive silhouette at the 4,000g split, and it never
    changes again up that path. Exactly the Basic roster's rule at its own 150g
    split
  - WHICH TIER is the same cumulative ladder on the elemental prices: the tower
    grows, its trim metal ramps, its accent brightens, a collar appears at 800g,
    bolts at 4,000g, fins at 10,000g, and a turning ring floats above an
    Ultimate
  - an elemental tower ALWAYS carries metal, from its cheapest tier. It is
    bought with a technology and nothing bought that way should read as the
    cheapest thing on the field - which is the opposite of the Basic 10g rule
    and is deliberate
  - **the 200g and 800g towers are ONE SHAPE AT TWO SIZES**, unlike the Basic
    10g/30g pair. That pair is barely the same object because it is the first
    upgrade any player ever buys; an element's base pair is bought seconds apart
    by somebody who already knows what they are doing, and should read as a
    direct upgrade
- **A tower's accent must not saturate to white at the top of the ladder.** The
  first pass ramped the elemental glow far enough that every Ultimate's accent
  came out the same colour, so an Ultimate Doom Guard and an Ultimate Lich lit
  up identically - the element was gone at exactly the tier the player has paid
  most for it
- **Motion above the Ultimate rule**: the turning ring stays an Ultimate's
  alone, at every tier of every element. What IS allowed lower down is a small,
  slow idle breath on the elements that are alive rather than built - Void,
  Unholy, Water and Primal
  - a creature that is perfectly still reads as dead, which is a worse lie than
    the motion is a distraction
  - it is authored an order of magnitude smaller and slower than a halo and
    sits at the middle of the model rather than at its outline, so the two
    cannot be confused at a glance

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
  - Which letter each square answers to is authored in the controls
    config and written down nowhere else
  - So one square is always one key, whatever unit happens to be selected
  - An ability names the SQUARE it claims rather than a key. Anything claiming
    no square falls into the first free one
  - Sell claims the same square on every card that has one
  - the Cancels - build, sell and upgrade - share a square of their own, so
    calling something off is one key wherever you are. They are never on a card
    at the same time as each other, since a building can only be doing one of
    the three
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
  - Unit portrait on the left with current and max health below it, and mana
    below that for the towers that have any
    - the mana line is left out entirely for everything else, which is every
      Basic tower and every creep. A line reading "0 / 0" on all of them would
      be noise on the panel a player looks at most
    - the portrait is a LIVE 3D view of the unit, not a picture of one: a real
      camera looking at a copy of the unit's own meshes, turning slowly, on a
      transparent background so the panel shows through behind it
    - live rather than baked because it cannot then go stale. A tower that
      upgrades, or anything that ever gains a variant, is already shown
      correctly, because what is being shown is the thing itself
    - it leaves out what is not the unit: the selection ring, the health bar
      and the ground patch a building stands on are all UI or floor
    - it is framed on the unit's own size, so a 10g tower fills the corner as
      much as a 25,000g one. Tier is told by trim colour, never by how much of
      the frame something takes up
  - Unit name, damage with its damage type, and armour with its type in the middle
    - The damage line is left out entirely for anything that cannot attack, so a
      creep's panel carries no line that only ever says "not this one"
  - Below those, attack speed and range, on a line that is left out entirely
    for anything that cannot attack
  - A command card grid on the right holds that unit's available commands
    - 4 squares across by 3 down. Most units leave most of it empty, which is
      the price of the send building and the build menu having room
  - A slot carries its ability's hotkey letter small in the top left corner,
    leaving the middle of the slot to the icon
  - A PASSIVE shows the picture of the thing it belongs to - an elemental
    tower's named ability draws that tower - because a passive is a rule rather
    than a thing and has no art of its own. An iconless square is a hole a
    player learns to skip over
  - **A passive never takes a square worth a hotkey.** It draws no letter, but
    it still occupies the square that letter is bound to, so one at the front
    of the card spends the best key in the game on something that can never be
    pressed. Elemental towers put theirs in the square furthest from the
    ones worth pressing
  - **Return to Elemental Core always claims the same square**, whichever
    element and whichever tier is carrying it, so the way back down is one key
    across the whole roster rather than a position that shifts with the card
  - **An UPGRADE takes the best squares on the card, and a BRANCH takes the
    first two, side by side**, in path order: first path first, second path
    second. Choosing a path is the most consequential press in the game, so it
    is the same two squares on every tower that branches, Basic and elemental
    alike. A tower with one upgrade takes the first square on its own, so the
    key that moves a tower up its line is the same key at every tier
  - Every ability that produces a UNIT shows that unit as its icon: the tower a
    build or an upgrade places, the creep a send buys
    - the icons are PLACEHOLDERS and are generated, one render per unit, from
      the same primitive models the game draws. They are expected to be
      replaced along with those models. See 2DArt/Icons
    - every one is framed on its unit's own size, for the reason the portrait
      is: a card of towers should compare their shapes, not their heights
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
- The RESEARCH CENTER opens from a button over the unit panel, and is the one
  screen that is not about the selection: it belongs to the player
  - a grid of every technology, laid out exactly as a command card is - the key
    is read off the SQUARE and the square draws the letter it answers to, so
    the shape is learned once for both
  - it is deeper than a card can be, so its bottom rows are the same letters
    with Shift held
  - while it is open it owns those keys: Q is a technology rather than whatever
    the selected unit's card puts there. Escape closes it
  - a square is lit once it is researched and greyed while it cannot be bought.
    Hovering one says what it would cost, what it leads to, and why it is
    refused when it is
  - two buttons at its foot: roll a random Ultimate, and undo
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
  - The name and stat lines are replaced by a grid picturing every selected
    unit, each tile showing that unit's own icon
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
  - The command card's letter keys are deliberately not used for the camera,
    they are reserved for ability hotkeys
- A center-on-target function exists to snap the camera to the builder or any other unit or building
  - Reached by tapping a control group's number twice
- Panning is bounded to the whole map, plus the send strip above the top row so
  the send building can be reached. The bound is the MAP rather than the areas
  in play, so the empty slots of a small match can still be panned over
- The mouse wheel zooms, between the default view and a close inspection one
  - **The default view is the FURTHEST OUT the camera goes.** A match opens
    there and the wheel only ever moves in, so how much of a lane a player sees
    stays the one number the whole layout was tuned against, and zoom can never
    become a way to see more of the map than the game intends
  - the closest setting is stated as how much of a lane's WIDTH it shows, in
    player cells, rather than as a camera distance. A tower is one cell, so the
    number reads directly as "how many towers fill the screen" and it survives
    the pitch or the field of view being retuned
  - one notch is a constant RATIO rather than a constant step. A constant step
    crawls when close and leaps when far out
  - the point under the cursor stays under the cursor, so pointing at a tower
    and rolling in arrives at that tower. The same thing the middle drag does
    with the point it grabbed
  - it changes only what this machine draws, so it is never a command
- TBD: controller equivalent of edge panning, and of zoom

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
- The grid is toggled by a BUILDER ABILITY, so the key follows its card slot
  like every other ability rather than being a binding of its own
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
- While any ability is waiting for its target, the command card clears down to
  a single CANCEL
  - Nothing else can be pressed or hotkeyed until the order resolves or is
    cancelled. The grid keeps its place, so the panel never changes shape
  - Applies to Move, to Attack and to placing a tower alike
- A card showing a SUBMENU carries the same Cancel, which returns to the unit's
  own commands
  - one button and one key for both, because to a player they are the same
    thing: "I did not mean to press that"
  - it sits in the square the other Cancels use, so backing out is one habit
    rather than three, and it is left OFF the card entirely when there is
    nothing to back out of rather than shown greyed - a card that always
    carries a dead button teaches a player to ignore that square
  - Escape and a right click still cancel too. The button exists to make the
    option VISIBLE, which a key nobody mentioned is not
  - it backs out of ONE thing per press: the order being aimed first, then the
    menu it was aimed from
- An attack has a WINDUP: the gap between it starting and its damage landing
  - it is the window an attack animation plays in - a hammer rising and
    falling, a barrel rocking back - so a tower that swings can land its blow
    on the frame the swing arrives rather than a moment before or after
  - **it comes OUT of the attack period, never on top of it.** A 1 APS tower
    with a 0.1s windup still attacks once a second: what changes is where in
    that second the damage lands, not how often it lands. A windup that added
    to the cooldown would make every animation a silent balance change
  - a tower COMMITS when the windup starts. It has picked what it is hitting
    and cannot be retargeted mid-swing, or the animation would play at one
    creep and land on another
  - a creep that dies during the windup does not waste the swing: it lands
    where that creep stood, so a splash still catches the crowd around it. The
    same rule a projectile already follows when its target dies mid flight
  - a tower that stops being able to attack mid-swing - one that starts
    upgrading - drops the swing. The cooldown is not handed back
  - a windup is authored only where there is an animation to fill it. A delay
    with nothing playing in it is one a player cannot see the reason for
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
  - A SKITTERING creep is considered only once nothing else is in range at all,
    whatever the priority says. That is a priority and not an immunity: a tower
    with nothing else to shoot shoots it, and an attack ORDER lands on it
    normally, so one can always be picked out by hand
  - Measured along the route that creep actually committed to, so one that took
    the long way round counts as being where it really is
  - Other priorities exist in the data - closest, strongest, weakest - and no
    tower uses them yet
- A tower still going up cannot attack. One being sold still can, since the
  sale can be called off and it is still standing
- A DESTROYED tower leaves RUBBLE on its cells for a few seconds
  - the cells go back to being walkable immediately: a destroyed tower stops
    being a wall the moment it falls. Only BUILDING there waits
  - which is what stops an attacker creep's work being undone the instant it
    finishes, and it is the only thing rubble does
  - selling a tower leaves none, so a player can never lock their own cells
  - NOT REPLICATED: rubble is marked by the authority, which is the only
    machine that knows a tower was destroyed rather than sold. A client's build
    ghost can therefore read green over a cell the server refuses for those few
    seconds. See multiplayer.md
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
  - SOME splash is measured from the TOWER instead, and that is a different
    effect rather than a setting on the same one
    - it is for a tower whose reach is barely more than its own cell while its
      blast is several times that: what such a tower really does is flatten
      the ground it stands on, and measuring that from whichever creep it
      swung at would move the damage around for no reason a player could see
    - a creep BEHIND such a tower is caught, though nothing could ever have
      been targeted there. That is the point of it
    - the creep that was hit still takes the attack's own damage first, and is
      then skipped by the blast, exactly as an ordinary splash does
    - the Crusher branch is what this exists for. See `unit_data.md`
  - Chain and LINE patterns are the other two shapes, and both are a WALK over
    creeps rather than a radius: a chain hops from creep to creep, each hop
    starting where the last one landed, and a line strikes everything standing
    between the tower and its target. Neither is area damage
  - STATUS EFFECTS are what an attack leaves BEHIND on a creep, and they are
    the creep's rather than the attack's. See Status effects below
- MULTISHOT picks one primary target and then that many further creeps standing
  near it, so multishot 2 attacks 3 creeps in total
  - "Near" is one distance shared by the whole game, not a per tower value. An
    ability may name its own where the source game gives it one
  - it is deliberately NOT area damage: it picks several single targets rather
    than covering ground, so a creep that resists area damage gets no help
  - a splash runs once, on the primary target. A multishot that also splashed
    per extra creep would multiply a splash tower's output by whatever happened
    to be standing about
  - a projectile attack fires one projectile per target

# Towers - which ones exist
BUILT: the whole Basic roster and the whole ELEMENTAL roster. Three Basic lines
splitting into six branches, ten elements splitting into twenty paths, and every
tier of all of it reachable by upgrading. The roster, the upgrade chains, the
names and every number are in `unit_data.md`: basic towers in its section 3,
elemental towers in section 4, the naming scheme in 2.4, and the technology that
gates the elemental ones in section 2.

The rules that hold whatever the roster says:

- Basic towers are available from the start and need no research
- Elemental towers require TECHNOLOGY, and the gate is on the button that buys
  them: an upgrade names the technology it needs, and it is refused - by the
  server as well as greyed on the card - until the ordering player owns it
- A tower is upgraded rather than replaced: an upgrade chain carries one name and
  a tier prefix, so a player follows one line rather than relearning it each tier
- Towers do not look like living creatures, WITH ONE EXCEPTION: an element whose
  towers are creatures in the source game may keep that - the Firelord, the
  Hurricane Elemental, and the Void and Unholy lines. They are given a base a
  tower can stand on and a footprint a maze can be built out of, and everything
  above it is free to be alive. It stays a setting constraint on art rather than
  a balance one

# The Elemental Core
BUILT.

### What of the elemental abilities is NOT built

Every elemental tower's named ability is implemented from `unit_data.md` section
4. Six pieces of them are deliberately left out or approximated, and they are
written down here rather than being quietly dropped:

- **Aether Attunement's manual target** (Ultimate Spellslinger). The source lets
  a player set the attuned creep by hand on a shared 30 second cooldown; here
  the tower attunes to whatever it is currently shooting. The automatic half is
  what the source does anyway when nobody sets one
- **Stampede Target** (Ultimate Beastmaster). The beast
  always runs at whatever the attack landed on, which is the source's own
  default. Aiming it by hand is a command card entry and a targeting mode
- **Crystalized Light's mana drain** (Ultimate Crystal). It drains the mana of
  creeps that use mana for their abilities, and creeps in this project carry
  none. The number is authored, the tooltip says so, and the effect does nothing
- **The technology sell refund.** `unit_data.md` 1.8 gives a technology tower a
  50% refund against a Basic tower's 60%. The refund share is one value shared
  by every building, so every tower currently refunds 60%. Splitting it is a
  rules change rather than content
- **Frostfire's per-tick slow** (Spellslinger line) is applied at its cap in one
  go rather than a step per tick of the burn, because nothing in the burn runs
  per tick. The depth reached is the same; the ramp to it is not
- **Frenzied Flames** (Ultimate Doom Guard) burns everything standing in the
  radius when the shot lands, rather than leaving a patch of ground alight for
  three seconds. The same damage over the same window, except that a creep
  walking INTO the flames afterwards is not caught. Worth revisiting when ground
  effects exist

- The builder places FOUR towers: the three 10g Basic ones, and the **Elemental
  Core** at 200g. Everything else in the game is reached by upgrading one of
  those four, which is what keeps the build menu four buttons long however deep
  the roster grows
- The Core is the technology base tower and is deliberately weak. It is worth
  buying only for what it becomes
- It MORPHS into any element whose Basic technology its owner has researched,
  and the morph is FREE: the 200 gold was paid for the Core and stays sunk in
  that cell, so the sell refund is the same either side of the morph
- Its card carries the ten elements behind ONE button rather than as ten of
  them. Ten squares plus its own three would want thirteen on a card that holds
  twelve, and which element you are choosing is a decision worth its own screen
  - every element is shown, including the ones not researched, and each says
    which technology it is waiting on. A player has to be able to read what the
    ten of them would cost before buying any
- An element's 200g and 800g towers are shared by both of its paths and belong
  to neither. The path is chosen at 4,000g
- Every elemental tower WORTH 800 GOLD OR MORE can **return to an Elemental
  Core**, which is the morph run backwards: the tower comes back down to a bare
  Core standing on the same cell, and the owner picks an element again
  - the Core's own gold STAYS SUNK in that cell and everything above it is
    refunded at the ordinary sell share, so the cell is worth a Core either
    side of the return, exactly as it is either side of the morph up
  - it is a MORPH rather than a sale, so the tower keeps standing and keeps
    blocking for the whole countdown and the maze never opens. It charges
    nothing, pays out when it finishes, and can be called off for free until
    then - all three the same way a sale behaves
  - the wait is its own number rather than the build time, because coming back
    down is a different job from going up
  - an element's 200g base tower does NOT carry it. It cost exactly what the
    Core cost and is already one free morph away from being one
  - what the tower had EARNED does not come down with it: banked damage, banked
    mana, anything a passive was keeping. A bare Core is what arrives

# Status effects
BUILT. What a tower's ability leaves BEHIND on a creep, as opposed to the damage
its attack deals.

They belong to the CREEP rather than to the attack, which is the same split the
damage pipeline already has: an attacker states what it does, and everything
about the defender is worked out on the defender. A tower says "chill this" and
never learns what the creep did with it.

- A creep nothing has touched carries none of them and pays nothing per tick.
  The set is created on the first one applied and dropped again the moment the
  last one runs out
- **Chill** is a slow that ACCUMULATES towards its own cap. Every slow in
  `unit_data.md` is written "X% per hit, up to Y%", so being hit again by the
  same tower goes deeper until that tower's cap is reached
  - each SOURCE keeps its own cap, which is what "up to 40%" means at all. Two
    tiers of one line do not share one
  - the WORST chill on a creep wins rather than the sum, so two towers each
    slowing 40% leave it at 60% speed rather than at 20%
  - a chill that runs out is forgotten rather than left at zero, so a creep that
    walked out of range and back in starts accumulating again
- **Stun** holds a creep still and stops it acting. **Paralyze** does the same
  to a flyer AND pulls it out of the sky: a paralyzed flyer can be shot by a
  GROUND tower, which is the one place air-versus-ground is not decided by what
  the creep is
- **Armour** moves two ways. PERMANENT erosion is gone for the rest of that
  creep's life, down to a floor the effect names - most stop at 0 and the
  Divineshroom line pushes to -3. A temporary CHANGE runs on a timer instead
- **Burning** is Spell Damage over time, and sources ADD: a creep set alight
  twice burns twice as fast
- **Amplification** makes a creep take more damage from everything, and there
  are two of them - one for Spell Damage and one for physical. They multiply
  alongside the creep's own resistances rather than replacing them
- **Poison** is a stack count with damage stored in it, kept on the creep so two
  towers stack into one explosion
- An **armour type** can be altered for a few seconds, once per type per creep
- Every "once every N seconds" rule in the game is one immunity key with a
  countdown, in one place, rather than a timer per effect
- NOT REPLICATED: a client is not told what is on a creep. It sees the creep
  where the server puts it, which is most of what a slow or a stun looks like,
  and the armour figure on a creep's panel is that creep's own. See
  `multiplayer.md`

# Mana
BUILT, and it is a TOWER thing: nothing else in the game has any.

- Nearly every elemental ability is "fill up by attacking, then spend the lot",
  so mana is the clock most of the roster runs on
- It is filled by REGENERATION, by ATTACKING, or by both, and each is the
  tower's own passive rather than a property of the tower
- One tower is built FULL and can never regain a point - the Doom Guard line,
  whose whole design is being at its strongest the moment it is placed
- One tower lowers its own MAXIMUM as it fires, and pulls its neighbours' down
  with it when that bottoms out - the Ultimate Orb Keeper
- Mana carries across an upgrade, along with anything else a tower's ability had
  banked: an Apprentice keeps its mana when it becomes a Sorcerer, and an
  Alchemist keeps the damage it has eaten. A tier that authors a starting share
  of its own overrides that, which is how the Doom Guard is built full
- Only towers that use any show a mana line on the panel


# Technology
BUILT, and so are the towers it gates.

The roster, the names, the prices and the twenty cross requirements are in
`unit_data.md` section 2. This says how the system behaves.

- Technology is bought by the PLAYER, not by a unit. It stands on no cell,
  nothing can attack it, and it is owned for the rest of the match
- Ten ELEMENTS, three technologies each: a BASIC one that unlocks the element
  at all, and two PATH ones that each unlock one of its two tower branches.
  Neither path can be bought before its element's Basic
- The first few are FREE and every one after that costs a step more than the
  last, so the price belongs to how many you have already bought rather than to
  which one you are buying. Every square quotes the same price and it climbs as
  the screen fills
- An ULTIMATE tower needs FOUR technologies: its own element's Basic and path,
  and the Basic and path of one specific OTHER element
  - which other one is a BIJECTION - twenty Ultimates, twenty element-paths,
    each of them the requirement of exactly one Ultimate, and never the other
    path of its own element. It is checked at boot rather than trusted
  - so four technologies is exactly one Ultimate, which is why a player who
    starts with four free ones is starting with a choice of Ultimate
- A press can be UNDONE for a few seconds, giving back the gold and the
  technologies
  - the unit of undo is the PRESS rather than the technology, so a random roll
    comes back whole
  - committing gold to the field closes the window early: starting a build or
    an upgrade ends it, because a tower bought under a technology must not be
    left standing by one that is given back
  - only the most recent press, and only inside its own window. The price
    depends on how many were owned at the time, so anything but last-first
    would refund a number that was never charged
- RANDOM ULTIMATE rolls one of the twenty and buys whatever its requirement is
  still missing, as one press. It only offers Ultimates the player can pay for
  in full, so the button never spends a click on an answer it cannot afford
- What a technology unlocks is BUILT: the Elemental Core morphs into the
  elements whose Basic technology their owner has researched, and each path's
  4,000g upgrade is gated on that path's own technology. See The Elemental Core
- NOT BUILT: the technology DISCS, which are a separate thing from the towers -
  see `unit_data.md` section 5

# Upgrading a tower
BUILT.

- **The builder only ever places the bottom of a line.** Everything above it is
  reached by upgrading the tower that is already standing
  - so the build menu stays four buttons long however deep the roster grows,
    and a player follows one line by pressing the tower they own rather than
    hunting a tier in a menu
  - a tower that splits into two branches simply offers two upgrades
- An upgrade is an ABILITY on the tower, so it goes through the same road every
  other order does and is refused by the same rules
- It needs no placement test and can never be refused for want of room: the
  tower is already standing on the cell the upgrade will occupy. It therefore
  cannot block a maze either
- The tower stays standing and keeps blocking for the whole countdown, exactly
  as a sale does
- It STOPS SHOOTING while it upgrades. It is being rebuilt, unlike a tower being
  sold, which goes on defending because the sale can still be called off
- Upgrading costs that TIER's own price, never the whole chain
  - the gold sunk into a tower accumulates, so the sell refund and the Value
    column both follow the total rather than the last rung climbed
  - cancelling hands back only the tier being paid for. Everything already sunk
    into the tower stays in it
- Upgrade time is the same as build time, for every tower at every tier
- **An upgrade shows what is being BOUGHT, not what is being replaced.** The
  new tier's model stands up and rises out of the ground over the countdown
  - only the LOOK changes early. The tower's stats, its card and its attack are
    still the old tier's until the upgrade completes, which is what keeps a
    cancel free and keeps every machine agreeing about what is standing there
  - cancelling puts the old tower's own visuals back
- **The upgraded tower is the SAME tower**: it keeps the cell it stood on, the
  gold sunk into it, and the name every machine calls it by, so a selection and
  a control group follow it across rather than emptying
- Double clicking still picks up ONE TIER rather than a whole line, since each
  tier is its own unit type

# Prioritize
BUILT.

- A toggle on every tower that can hit BOTH ground and air, sitting in the same
  square on every card that has it
- On, the tower shoots flyers while any are in range, and falls back to its
  normal priority when none are. That is a priority rather than a restriction:
  a tower set to watch the sky still shoots ground rather than standing idle
- Per tower, not per player and not per tower type, so two towers of one type
  can be set differently
- Offered by nothing that can only hit one of the two: on a ground-only tower
  there is nothing to prefer, and on the anti-air branch there is nothing else
  to shoot

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
  - BUILT, and dealt: most of the elemental roster's named abilities deal it,
    and the resistance side is Tier 1's Mud Golem

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
- Every TOWER carries armour type Fortified, whatever damage type it deals, and
  its armour POINTS come from its price tier alone. Two towers that cost the
  same have the same body however differently they shoot. See `unit_data.md` 1.4
  - the builder, the send building and the technology discs are Invulnerable
    instead, which is the absence of damage rather than a resistance to it

# Creeps
- Creeps enter at the top and walk to the bottom
- Spawn position is randomised: random x across the width, random y within a margin at the very top
  - Every creep of a pack rolls its own position, so a pack arrives spread out
- Creeps carry a worldspace health bar like any damageable unit
- Creeps take no orders from anyone
  - They can be clicked to inspect, showing the normal unit panel with an empty
    command card, but never selected by a selection box and never commanded
  - ATTACKER creeps are the exception, and the only one
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
- FLYING creeps ignore the maze completely. BUILT.
  - they read none of the occupancy grid, so a tower dropped in front of one
    does nothing at all, and one can never be set back by a tower going up
  - they fly straight down the lane at a fixed height and leak at the same end
    zone everything else does
  - only a tower that can hit air can reach them, which is what the anti-air
    branch has been waiting for
  - the height is visual only. Every distance in the game is measured flat, so
    nothing is ever out of reach for being in the air
  - they crowd only against other flyers: a pack walking underneath one is not
    something either of them can feel
- ATTACKER creeps go after the towers instead of past them. BUILT.
  - they are the only creep their owner can select, box-select and command, and
    they carry Move, Stop and Attack like any other unit
  - left alone, one walks to the NEAREST tower, destroys it, and moves on to the
    next. It never advances towards the end zone of its own accord, so stealing
    a life with one is something its owner has to ORDER
  - a move order means MOVE: it walks and does not stop to fight. An attack
    order cancels the move rather than fighting it
  - an attacker creep can only ever target a TOWER. The builder and technology
    discs cannot be attacked at all - not "are tough", not "are ignored while a
    tower is in range": they are not valid targets, ever. A maze wall made of
    discs is a wall an attacker cannot chew through, and that is deliberate.
    Enforced by their being invulnerable rather than by a list of exceptions.
    See unit_data.md
  - what it destroys leaves rubble, see Towers and attacking
- BOSS creeps are sent one at a time and steal TWO lives instead of one. BUILT.
  - the steal is still capped at what the defender has left, so a Boss can no
    more invent a life than any other creep can

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

**TIER 1 IS IMPLEMENTED**, all twelve of it plus the Timber Wolf that only ever
arrives inside a Sheep pack. The numbers are `unit_data.md` 6.2's, which are the
source game's; the creeps' `.tres` files are the authority and that section is
the mirror. The placeholder test set it replaced is gone.

Tiers 2 to 4 are not built. Nothing about the code is waiting on them - a new
creep is a stats file, a prefab and a send ability - but four of the traits they
need are, and each wants a system that does not exist yet: slows and timed
debuffs, mana, damage absorption shields, and creeps that spawn other creeps.

A SEND is a pack rather than a count: nearly every one is three of the same
creep, a Boss is one, and the Sheep is two Sheep and one Timber Wolf. What a
send spawns is the creep's own answer, so a pack that ever grows a second escort
is another entry in its file rather than a rule anywhere.

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
- Creeps unlock over game time, each on its own start delay. BUILT.
  - the delay is per CREEP and never per tier, one every thirty seconds in
    ascending cost order. The delays are in `unit_data.md` section 6
  - it also removes the need for a separate rule disabling sending at the start:
    at the first second only the Sheep is unlocked, so there is nothing else to
    send
  - a locked creep's square is drawn greyed out and its tooltip says when it
    opens. The server refuses one that arrives early whatever the button showed,
    since a client counts the clock itself
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
  wherever those creeps happen to be walking. BUILT.
  - a send is refused from the CAP UPWARDS, so a player at 98 of 100 may still
    send a pack of three and end up at 101. Population is charged per creep and
    a send is priced as a pack, so refusing a partial one would strand the last
    few places
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

- The TIER 1 creeps are no longer in that category: their numbers are copied
  from `unit_data.md`. Four things about them were still choices nobody
  reviewed, because the source records none of them:
  - the Corrupted Treant's attack RANGE and DAMAGE TYPE. Its damage came from
    you and its speed is your own unverified estimate, which `unit_data.md` 6.2
    marks as such
  - how far the Unholy Sacrifice death heal reaches. It is a burst rather than
    an aura, so it does not share the one aura radius
  - how much faster Fast Producing really is
  - how high a flyer flies, which is visual only and changes nothing
- The TOWERS are no longer in that category: their numbers are copied from
  `unit_data.md`, which copies the source game. Three things about them were
  still choices nobody reviewed, because the source records none of them:
  - the divisor turning the source game's range and splash figures into player
    cells. One number, and every reach in the game scales with it
  - which DELIVERY each branch uses - what flies, how fast, and how high it
    arcs - and the projectile speeds that go with it. The source has no
    projectile data at all
  - the visual language in Presentation above: the shapes, the six step trim
    ramp and what appears at which tier
- The ELEMENTAL towers are in the same position, and add four more choices
  nobody reviewed:
  - the ten HUES, and which element got which. `unit_data.md` records no colour
    at all - these are approximated from the source game's own art and then
    pulled apart from each other where two collided. The reasoning is in
    `Tools/ModelGen/style.py`
  - the base shape and side count of each element, and the twenty path
    silhouettes. The source game reuses mobile units as towers for most of
    them, so there was nothing to copy
  - the MULTISHOT reach: how near a further target has to stand. One number for
    the whole game, and the source only names a distance for one tower
  - the six abilities approximated or left out, listed under Towers - which ones
    exist. Each is a judgement about what was worth building now
- The send building's display name is still a placeholder
- Creep models are primitives varying only by shape, size and colour. Tower
  models are primitives too, but to a deliberate system - see Presentation
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
