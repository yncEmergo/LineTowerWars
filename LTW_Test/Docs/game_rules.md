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
- It can attack creeps, ground and air alike, with a short melee reach
  - Weak and slow: typically only relevant in the early game, and never a
    substitute for a tower
  - It takes an attack order like anything else that can attack, which for a
    unit that walks means an attack-MOVE - see Towers and attacking
  - **It only ever fights when it is TOLD to.** Unlike everything else that
    attacks, the builder never picks a fight of its own: a creep walking past
    its nose is ignored until the player orders otherwise
    - the builder's time is the PLAYER's rather than the simulation's. It is
      the one unit being steered by hand, usually in the middle of laying out
      a maze, and a hammer that swung at whatever wandered by would stop it
      dead over a few points of damage nobody asked for
    - an attack-move still hunts. That IS an order, and the whole of what it
      says is "go there and fight what you meet"
- Stats live in a per-unit resource: health, damage range, armour type, movement speed
  - Current builder values are placeholders and not balanced
- TBD (much later): full control scheme

# Presentation
**Everything in this section about how a unit LOOKS is Claude's, not the
user's, and none of it is a hard rule.** What was asked for is placeholder
visuals; the rules exist so a roster added later still looks like it came from
the same game as the ones before it. Where a line below says "rule", "never" or
"hard rule", read it as the convention the existing rosters were built to -
worth arguing with, and worth the argument, but not binding. The reasoning is
what to push against rather than the wording.

This does not cover the rest of the section. What the CAMERA does, what the
PANEL shows and what a countdown means are gameplay and are the user's.

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
- **What an attack LEAVES BEHIND on the target is a choice of shape, and the
  shape says what kind of hit it was**
  - a RING on the ground is an area. It is the default and most of the roster
    uses it, because the camera looks down and a flat ring is the only shape
    that really shows how much ground took damage
  - a SPRAY of particles is a single hit landing on a body. What comes off says
    what did it - heavy drops thrown back down the line for a blade chewing on a
    creep, small bright motes thrown in every direction for a discharge earthing
    itself. A tower with no area should not be flashing a disc that says it has
    one
  - an ARC strung back to the muzzle is a hit that never travelled. It is drawn
    from the tower to the creep at the moment of the strike and is gone in a
    fraction of a second, and it is the only effect that needs BOTH ends of a
    hit rather than just where it landed
    - an ability that reaches further creeps from one attack draws the same arc
      to each of them, so what a player sees is exactly the set of creeps that
      took damage. That is the whole value of it: a chain with no line drawn is
      damage appearing on a creep nothing pointed at
- **A tower may throw particles off ITSELF when it attacks**, at any tier
  - it is not idle motion and is not covered by the Ultimate-only rule below: it
    happens when something happens, which is the one kind of movement that is
    always worth a top-down camera's attention
  - the emitter is part of the MODEL and sits quiet until a component with a
    unit behind it fires it, so the build ghost carries one harmlessly
- **A tower on a clock says so in two places at once**: a bar over its head in
  the world, and a row on its panel where the stat lines usually are
  - it covers selling, upgrading and reverting to an Elemental Core. All three
    are countdowns the player started and can still call off, and all three
    look the same because what the player needs to know is the same: how long,
    and what will be standing there afterwards
  - the worldspace bar sits ABOVE the health bar, at a fixed height, so it
    stands in the same place whether or not the health bar is being drawn
  - it IGNORES the player's health bar setting and shows for the whole
    countdown. That setting is about clutter over a field of full-health
    towers; a countdown is a thing the player asked for and is waiting on, and
    hiding it would hide the only sign that a press landed
  - CONSTRUCTION is the exception and gets no bar of its own. A tower going up
    already shows its progress by its health climbing from 1 to full, and a
    second bar over the first would say the same thing twice
- **A tower with a SECOND RESOURCE says so over its head too**, in a bar under
  the health bar
  - usually mana, and not always: what it means is "the thing besides health
    that decides what this tower is worth right now". Every tower that has one
    draws it the same way
  - the not-always is a tower whose named ability BANKS something. Where one
    does, that count is its second resource and its mana is not - a tower that
    holds mana it can never spend has no bar worth giving it, and the number a
    player wants is the one the ability actually reads
  - a banked count is drawn in its OWN colour, so a bar that fills as a tower
    kills is never mistaken for one that empties as a tower fires
  - it sits UNDER the health bar, offset from where that bar would be rather
    than from the bar itself, so it stands in the same place whether or not the
    health bar is drawn - and like the job bar it ignores the player's health
    bar setting entirely
  - the two stacks read outwards from the health bar: what the tower is DOING
    above it, what the tower RUNS ON below it
  - a tower with none draws nothing, so the bar is never an empty rectangle
    over a tower it means nothing for
  - **and it goes away once it is FULL**, the same way a health bar does at
    full health. Full is the resting state of most of the roster - nearly every
    elemental ability is "fill up, then spend the lot" - so a lane of towers
    waiting to fire would otherwise be a lane of identical full bars saying
    nothing. A bar that is PARTWAY is the thing worth seeing, and the bar
    appearing at all is then the event
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
- The tower roster has a visual language, and what makes it worth writing down
  is that it survives the primitives being replaced by real art - it is what a
  3D artist should be handed along with the models. It is a convention rather
  than a rule, see the note at the top of this section
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
  - **WHICH TIER is NOT the Basic roster's metal ladder**, and this is the one
    place the two rosters answer a question differently rather than in the same
    shape. **METAL IS THE BASE PAIR'S ALONE.** The 200g tower wears one ring of
    near-black iron and the 800g tower wears two rings of polished brass, and
    **no elemental tower above 800g carries any metal at all** - no ring, no
    collar, no bolts, no fins, no floating ring over an Ultimate, and nothing
    else drawn in the tier material
    - the roster shipped wearing the whole Basic ladder and two things went
      wrong with it at once, each making the other worse. The metal was the
      LOUDEST thing on every tower, so thirty different silhouettes read as one
      silhouette with its top swapped; and two neighbouring rungs of a six step
      metal ramp are nearly the same colour, so the thing being shouted was
      also the thing hardest to read
    - metal survives on the base pair because there it is the only thing that
      CAN do the job: those two are deliberately one shape at two sizes, so a
      ring is the whole of what separates them. Their two rungs are therefore
      pulled as far apart as two metals get - dark iron, then bright brass -
      rather than being two steps of one ramp
  - **so a path tier is read off the STONE, the MASS, the SHAPE and, at the
    top, MOTION**
    - the STONE is the direct replacement for the metal ramp and does the same
      job: the element's own material is darker and duller at Lesser, stands as
      authored at Greater, and is brighter and more saturated at Ultimate. One
      continuous value ramp, readable at any distance, on any shape - and
      unlike the metal it is the ELEMENT'S own colour rather than a second
      palette laid over the top of it
    - the ramp moves VALUE and SATURATION and never the HUE, or an element
      would stop being that element halfway up its own line
    - it is applied with the HEADROOM the colour actually has: an element that
      is already near-black darkens barely at all, and one that is already
      ivory brightens barely at all. A flat multiply is wrong at both ends -
      it takes a Fire Lesser to an unlit lump and does nothing whatever to a
      Holy Ultimate
    - **a PATH is THREE SILHOUETTES, not one with parts added.** Each of the
      three tiers re-cuts the shape rather than bolting another piece onto it:
      a rock sitting in a cradle becomes a burning orb held above it becomes a
      green one hanging over a cradle that has cracked open; a shut strongbox
      becomes one with its lid ajar becomes one thrown wide; one mushroom
      becomes three becomes five. That is what the ladder spends now that it
      cannot spend metal
  - **a PATH may claim ONE PART of its own model in a colour the element does
    not have**, and only where the source art makes that part the entire point
    of the tower
    - it is the one exception to colour belonging to the element, and it is
      narrow on purpose: one part, named per tier, on a tower whose reference
      art is three different objects rather than one object three times
    - everything else on that tower still wears the element's hue, so the
      element is still what a player reads across a map
    - it goes through the same lit-accent shader as any other glowing part, so
      it still brightens with the tier and pulses like the rest of the roster.
      Only the hue is the path's own
  - an elemental BASE tower always carries its ring, from its cheapest tier. It
    is bought with a technology and nothing bought that way should read as the
    cheapest thing on the field - which is the opposite of the Basic 10g rule
    and is deliberate
  - **the 200g and 800g towers are ONE SHAPE AT TWO SIZES**, unlike the Basic
    10g/30g pair. That pair is barely the same object because it is the first
    upgrade any player ever buys; an element's base pair is bought seconds apart
    by somebody who already knows what they are doing, and should read as a
    direct upgrade
- **A tower's accent must not saturate to white at the top of the ladder.** The
  first pass ramped the elemental glow far enough that every Ultimate's accent
  came out the same colour, so an Ultimate Moonbeam and an Ultimate Lich lit
  up identically - the element was gone at exactly the tier the player has paid
  most for it
- **Motion above the Ultimate rule**: an ELEMENTAL Ultimate, and only an
  Ultimate, gives off a slow continuous rise of motes in its own element's
  colour. That is what the turning metal ring used to be, and it is a strictly
  better version of the same rule - motion is still the loudest signal a top
  down camera has and is still reserved for the top rung, but now it says WHICH
  element as well as how expensive, in a material the roster still uses
  - it is a STATE rather than an event, and is authored so quiet that what it
    says is that the thing is giving something off, not that something is
    happening to it. The particles a tower throws when it ATTACKS are the
    opposite and are allowed at any tier
  - a Basic Ultimate keeps its turning ring. That roster has no colour to give
    off, which is the whole reason it has the ring
  - what IS allowed lower down, on both rosters, is a small, slow idle breath
    on the elements that are alive rather than built - Void, Unholy, Water and
    Primal
    - a creature that is perfectly still reads as dead, which is a worse lie
      than the motion is a distraction
    - it is authored an order of magnitude smaller and slower than the aura and
      sits at the middle of the model rather than at its outline, so the two
      cannot be confused at a glance
- **A tower does not have to be a TOWER.** A path may give up its plinth
  entirely at its top tier and hang in the air instead, where that is what the
  thing actually is - Arcane (2) ends as a portal orb turning over bare ground
  with no structure under it at all
  - what it may NOT give up is the ground patch. That patch is what says a cell
    has been built on, and a tower floating over untouched grass reads as
    something passing over the maze rather than as part of it

- **The CREEP roster answers the same three questions again**, and it is a rule
  in the same way both tower rosters are: it survives real art replacing every
  model, and it is what a 3D artist should be handed with them
  - WHICH FAMILY is what the creep does to the MAZE, and it is the only
    question a player has to answer in the second before one arrives. It is
    deliberately not the creep's TIER: a tier is a cost bracket and carries no
    mechanical meaning, so making it the loudest signal would teach a player
    something untrue. Three families, three conventions held firmly:
    - a GROUND creep stands on legs, on the floor, and is opaque
      - being drawn as VAPOUR belongs to what a creep IS rather than to how it
        travels: a wraith is made of it, and so is the one ground creep that
        walks straight through your towers. It is named per creep rather than
        derived from a body plan, so it stays a rule somebody changed
    - a FLYING creep has NO LEGS AT ALL, hangs at its cruising height, is drawn
      translucent and unlit, and is the only thing in the game with a SHADOW
      DISC pinned to the ground beneath it. The disc is the tell, not the
      altitude: from a top down camera a flyer at height and a flyer on the
      floor are the same picture, so the height is worth nothing on its own
    - an ATTACKER creep is the only creep whose WEAPON IS LIT. Every other hard
      part in the roster is unlit - bone, claw, iron, a Swordsman's sword - so
      the one thing on the field with a hot edge is the one thing coming for
      your towers rather than past them. It is about the LIT edge and not about
      carrying a weapon, because half the roster carries one and almost none of
      them ever swing it at a building
  - WHICH CREEP is its body plan and its hide colour. The plans are the shapes
    a roster of creatures actually needs - four legs, two legs, eight legs, a
    hulk, a floating wraith, a walking tree, a winged beast, a shell, a
    machine, a coiled serpent - and two creeps on the same plan are pulled
    apart on the things that change the OUTLINE rather than the detail: how far
    the torso stoops, whether legs are replaced by a hem, what the head is,
    what the hands hold
    - a NEW PLAN is only for a creature the existing ones would have to LIE
      about. A naga has no legs, so drawing a pair on it was the bar the
      serpent plan cleared; nine more bipeds were not
  - HOW STRONG IT IS is a stepped ladder on the creep's own GOLD COST, and it
    is worth more here than on towers: a creep cannot be upgraded, so a player
    has no other way to learn the ordering. It runs on cost rather than on tier
    so that it is one ladder across the whole roster - a bracket does not
    restart it - and it climbs the same way the tower ladder does, with
    continuous rules keeping neighbours apart and stepped ones making the
    dangerous ones readable across a map:
    - the creep grows a little, its EYES brighten, and its CARAPACE - every
      claw, horn, plate and weapon on it - ramps from raw bone through to
      blackened steel
    - plates arrive over the shoulders or flanks, then a row of spines down the
      back, then a crest of horns. WHERE each goes is the body plan's business;
      what the ladder fixes is that it is there
    - the carapace ramp runs from PALE TO DARK, opposite to the tower trim
      ramp's iron to white gold, so a creep's hard parts can never be read as a
      tower's tier metal halfway up either ladder
  - **SIZE IS THE ONE RUNG OF THAT LADDER THAT IS CAPPED, and the cap is held
    more firmly than the rest.** The whole roster - the cheapest creep in the
    game and the last Boss of Sudden Death - lives inside ONE NARROW BAND of
    sizes, and between one TIER and the next the difference is MINOR at most
    - two reasons, and both are about the player rather than about the
      fiction. A tier carries no mechanical meaning, so a tier 4 creep
      towering over a tier 1 creep would be the loudest thing the roster ever
      says about a creep and it would be untrue. And a field of creeps two and
      three times each other's size is chaotic to read whatever it is saying
    - the CEILING of that band belongs to a TOP TIER BOSS - the Behemoth, or
      Sudden Death's own - and nothing else in the game may come near it
    - so what a size ladder is FOR here is keeping neighbours apart, and
      nothing else. How dangerous a creep is rides on the eyes, the carapace
      and the added plates, spines and crest, and those may climb as far as
      they like, because none of them costs a player the ability to read the
      field
    - a creature that simply IS a bigger animal than its neighbour may still
      be drawn bigger, inside the band. What is not allowed is bigger because
      it is a later tier
    - **a BODY PLAN may be corrected as a whole, and that correction is a
      rule rather than a per-creep nudge.** A plan is authored to look like
      the creature it is, and some of them then read the wrong SIZE for the
      field however faithfully they are drawn - a humanoid is tall and narrow
      and the overhead camera reads narrow as small; a spider counts its legs
      in its footprint and reads as far heavier than it is. Where that is
      true it is true of EVERY creep on the plan, so the correction belongs
      to the plan and moves all of them together. A single creep that is
      still wrong after both its rung and its plan gets its own multiplier,
      and a table of those that grows past two or three is the rung ramp or a
      plan being papered over one creep at a time
    - a BOSS is the one thing allowed a noticeable step, and it is still a
      fraction rather than a multiple - see the Boss rule below
  - **the ladder RUNS OUT if nobody checks it, and it did.** It is measured in
    half decades of gold, so the cheapest creep in the game and the most
    expensive stand eleven rungs apart - and the ramps were authored with six.
    Everything above the sixth rung was quietly clamped onto it, which by the
    end of tier 2 was a third of the roster wearing one carapace and one eye
    brightness. Adding a bracket is a reason to count the rungs it needs
  - a BOSS is forced onto the top of that ladder whatever it costs, and takes a
    size bonus on top. It is sent one at a time and steals two lives, so it has
    to read as the biggest thing in its bracket before a player has read
    anything else about it
- **A creep's only lit parts are its EYES**, in one amber that is the same on
  every creep in the game, brightening as the ladder climbs - plus an
  attacker's weapon edge, which is that same amber and is the one exception
  - a player learns "brighter eyes, tougher creep" once and it holds for the
    whole roster, which is worth more than a per-creep eye colour at the size
    an eye is actually drawn
  - it is also what separates a creep from an ELEMENTAL tower, which glows over
    its whole body. Creeps carry hide colour and elements carry light
- **A creep's hide says WHICH CREEP, never WHOSE.** Ownership is the minimap's
  job. Tinting a creep by its sender would cost the roster the one axis that
  tells a Sheep from a Skeleton, and an in-world owner tell - if one is ever
  wanted - has to be a separate device such as a ring on the ground
  - creep hides are MUTED and are chosen against the ten elemental hues rather
    than around them. Where one lands near an element that is a deliberate
    outcome and not a collision: mud is earth coloured. What keeps the two
    apart is everything else - a creep is unlit, organically banded rather than
    panelled, and stands on no foundation patch
- **Every creep walks**, and the walk is measured in DISTANCE TRAVELLED rather
  than played on a clock
  - a creep chilled to half speed takes half as many steps in the same second,
    a stunned one stands still, and a big creep covering the same ground takes
    fewer, longer strides. None of that has to be told to the animation
  - it is also what makes the walk work unchanged on a client, which runs no
    simulation and only sees the position the server sent
  - a flyer has no legs to measure a stride with, so its drift is on a clock
    instead and what it swings is the rags trailing under it. A creature that
    is perfectly still reads as dead, in the air as much as on the ground
- **A killed creep pops the gold it paid**, in the air over the spot it died on
  - bounty goes to whoever owns the maze, and a tower defence is watched at the
    maze rather than at the resource bar, so the payout is drawn where the
    player is already looking
  - it is the same number on every machine watching, and it costs nothing on
    the wire: the authority draws it as it pays the bounty, and a client draws
    it when the creep leaves the snapshot
- **A send building says which TIER it is by a COUNT, never by a colour or a
  size.** One pip on its face per tier, and the buildings are otherwise
  identical
  - counting is what survives the buildings standing next to each other in a
    row, which is how they are always seen. A size ladder would say "stronger"
    about a thing that is not stronger, and a colour would spend a hue the ten
    elements own
  - the position on the strip already says the same thing, and that is the
    point: the pips are the redundant half, for a player who has not learnt the
    order yet

# Controls
- Mouse controls follow the WC3 standard
  - Left click selects a unit, or gives an attack order when the click lands
    on a creep and the selection can shoot it
  - Left click and drag draws a selection box
  - Right click on walkable ground issues a move order to the selection
- A multi selection only ever holds one KIND of unit, from one owner
  - Kind is coarser than type: every tower is one kind, so any tower can stand
    in a selection beside any other whatever its element, branch or tier
  - Towers, mobile units, the senders and the technology discs are all
    different kinds and are never mixed in one selection
  - A selection BOX is narrower still and comes back with one exact TYPE: the
    type of the unit nearest where the drag STARTED, and that unit leads the
    selection. So putting the pointer on the Archer you want and sweeping
    across a mixture hands back the Archers
  - The START of the gesture rather than the middle of the box or the type it
    caught most of, because the start is the one point the player actually
    aimed at: the box then grows to wherever they happened to let go
  - Assembling a selection of several types is what shift is for, below
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
  - Any unit of the selection's KIND can be added, so shift is how a mixture of
    tower types is put together - a box would have kept only one of them
  - A shift box adds everything it touched that may join, without narrowing to
    one type: the selection already says what is wanted
  - Shift clicking empty ground keeps the selection rather than clearing it
- Double clicking a unit selects every unit of exactly that type
  - Exact type, not kind: double clicking a Basic Tower picks up Basic Towers
    only, never other tower types, and never other upgrade levels
  - Every one of them on the field, where a box is limited to what it drew
    around, which is the difference between the two
  - Own units only, so an enemy's identical towers are never caught
  - The window is 0.5 seconds for now
- Control groups on the number keys 1 to 9
  - Control plus a number assigns the current selection to that number
  - The number alone recalls that group
  - A group holds whatever was selected, so a group of mixed tower types is
    normal - assembled with shift - while a group of towers plus the builder
    cannot be put together in the first place
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
  - An ability keeps the key of the square it CLAIMED even when it has to sit
    on another one, so one ABILITY is always one key. A square it was moved
    off is then drawing somebody else's letter, which is the only thing that
    ever separates the two
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
  - The rows are written for a GERMAN keyboard, and the options screen swaps
    the one letter an American board wants moved. Nothing else about the grid
    is a setting: the letters are the game's, learned once
  - The letters live in Resources/Config/controls_config.tres, one string per
    row, so relaying the card out never means editing an ability
- A SHORT AUTHORED LIST of commands answer to a key of their OWN instead, off
  the grid, and those keys the player may rebind
  - It is deliberately short and always will be. There are hundreds of
    abilities and twelve squares, which is the whole reason the grid exists;
    what earns a key of its own is a command that means the same thing on
    every card a player ever opens, and so is reached for by NAME rather than
    by position
  - a key the grid already carries can never be given to one, in either
    keyboard layout, so a press never means two things at once. The keys the
    game answers wherever you are - the control groups, the ones that back out
    and open the menu - are refused for the same reason
  - one key, one command: binding a key takes it off whatever held it before,
    which is then left with no key until it is given one
  - a command may also be left with NO key, which puts an ability back on the
    square it sits in and hands it that square's letter again
  - the Research Center's own key is one of these, and is the only one that is
    not on a card at all
- Such a command may claim its square AHEAD of the grid, and whatever wanted
  that square is pushed to the next free one, counting on from it and wrapping
  round the card
  - it has to be able to: its key no longer comes from where it sits, but the
    square it wants is usually one the grid has already promised somebody else
  - the pushed ability keeps its key and takes it along to the new square. So
    a command with a key of its own costs the card a SQUARE, never a key
  - ONLY the ability that wanted that exact square moves, and only if it is
    really there. Nothing else on the card is shuffled to make room, and a
    card that was not using the square notices nothing at all
  - the card is laid out square by square rather than in card order, so a
    displaced ability slides its neighbour along in turn instead of leaping
    over it to the first hole further down
  - a card with nowhere left to push to is an authoring mistake and says so
- Holding SHIFT while giving an order CHAINS it behind whatever that unit is
  already doing, instead of replacing it
  - Only the orders that TAKE TIME can be chained, which is Move, Attack and
    Build. Everything else on a card happens the instant it is pressed, so
    there is nothing to queue and nothing it could ever wait behind
  - A chainable order given WITHOUT shift wipes the whole chain and starts
    again from that one order. Anything that is NOT one of the three leaves
    the chain alone: flipping a toggle or reading a range must not cost a
    tower the creeps it was told to shoot
  - Stop empties the chain as well as halting what is running, and it is the
    one non-order that touches it. That is what a player means by pressing it
  - A task is finished, and the next one starts, when:
    - MOVE: the unit is standing on the point. An order aimed outside the area
      ends where the unit could actually get to, which is the rule an unchained
      move already follows
    - BUILD: the tower has been STARTED, not finished. The builder is free the
      moment it starts one, so that is the moment it moves on
    - ATTACK: the unit it named is dead, or an attack-move has reached its
      point with nothing left in reach
  - A task that cannot be carried out when its turn comes is DROPPED and the
    chain carries on. A build spot taken while the builder walked over, and a
    tower there is no longer gold for, are the two that really happen
  - A chained click LEAVES the ability armed: the card keeps showing it, the
    ghost keeps following the cursor and the reach stays drawn. So a row of
    towers is one press of the button and one click per tower rather than a
    trip back to the card between each
  - **The arm lasts exactly as long as SHIFT IS HELD.** Letting go releases it.
    The chain itself carries on - it was given to the unit and has nothing to
    do with the card any more - and the player is free to start something else
    on the same unit, a different building included
  - Without that lifetime the ability outlives the gesture that meant it: place
    the last tower of a row, let go of shift, click to pick something up, and
    you would have placed another tower there instead
  - Shift is still the key that adds to a selection, and the two never
    collide: a click that lands on something the selection can attack is an
    ORDER before it is ever a selection, so the same press was never doing
    both
- A queued order that names a PLACE marks that place on the ground, and the
  two kinds of mark say different things
  - a walk still to be made leaves a small standing waypoint, drawn only while
    that unit is selected. There is one builder and a handful of attacker
    creeps, and a lane wearing every dot all of them are walking to would be
    unreadable
  - an ATTACK-MOVE names a point the same way and means something else there,
    so its waypoint is RED where a walk's is green. The same red the attack
    order's ring uses, so "this is an attack" is one colour across the whole
    interface rather than two that nearly match
  - a tower ordered and not started leaves a GHOST of itself, drawn whether or
    not the builder is selected - it is a decision about a piece of ground
    rather than a note to the unit. It also HOLDS that ground: aiming the next
    tower over one shows the placement as illegal, so a chain of five cannot be
    stacked on one spot
  - a ghost is GREY when there will still be gold for it and RED when there
    will not, counting everything queued in FRONT of it as already spent.
    Thirty gold and five ten-gold towers is three grey and two red, and the
    colours move the moment the gold does - a send, an upgrade, income arriving
  - the same red an illegal placement uses, deliberately: both say the same
    thing, that this will not happen, and a second colour for it would be a
    distinction to learn for no gain
  - the ghost under the CURSOR says it too, on the same terms and before the
    click rather than after: it counts every tower already ordered and not yet
    started as spent, so a chain of five on thirty gold turns red at the
    fourth, and a single one turns red the moment the gold for it goes
    elsewhere. It is a warning and not a gate - betting on income arriving
    during the walk is a legitimate thing to ask for
  - the ghost is not only for chains. A single build order the builder is
    still walking to shows one too, from the click until the tower starts
  - an attack aimed at ONE unit leaves neither mark. What was chosen is the
    target, and the ring that blinks on it is already the answer
  - both are FEEDBACK and never leave the machine, like the selection, the
    build ghost and the range overlay
- Gold is spent when a tower STARTS, never when the order is given
  - so a chain may be longer than the gold in hand: income arrives while the
    builder walks, and a tower it still cannot pay for when it gets there is
    dropped
  - a plain build order is still refused up front, which is what greys the
    button. Shift is what asks for the other behaviour
- TBD: controller scheme
# Interface
- A unit panel sits at the bottom of the screen while exactly one unit is selected
  - Unit portrait on the left with current and max health below it, and mana
    below that for the towers that have any
    - each of the two is a BAR as well as a number, the bar above the number it
      belongs to. The bar is what is read at a glance mid-fight, the number is
      what is read when the player actually wants to know
    - the second bar is whatever that unit's second resource is. Mana for the
      towers that spend it, and the same bar carries a tower whose named
      ability fills up rather than spends - a Voidling growing towards the
      point it transforms at is reading its own mana
    - and it carries a COUNT for a tower whose ability banks one, in that
      count's own colour. Same bar, same line under it, same rule about being
      left out entirely where there is nothing to say
    - neither bar is affected by the worldspace health bar setting. That
      setting is about clutter over the field; a panel is open because the
      player selected something and is always answering a question they asked
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
  - A tooltip appears the MOMENT the cursor lands on the thing it describes.
    There is no hover delay anywhere in the game: half of what a card says
    lives in its tooltips, and a wait before reading one is a wait paid on
    every question a player asks of the interface
    - a tooltip already on screen is rewritten in place when what it describes
      changes. An ability whose only feedback is its own tooltip - the armour
      type an Ultimate Alchemist is set to - would otherwise read as a dead
      button, because the cursor never left the square for Godot to notice
  - Unit name, damage with its damage type, and armour with its type in the middle
    - The damage line is left out entirely for anything that cannot attack, so a
      creep's panel carries no line that only ever says "not this one"
    - **it is the damage the thing standing there actually rolls**, not the
      number on its stats - read as the plain figure and whatever is tinted
      beside it together. A tower that has permanently grown has the growth
      folded into the range and repeated on the end, so the line answers both
      "what does this hit for" and "how much of that did it earn". Same rule
      the armour line already follows, which shows the points a creep has left
      rather than the points its type was authored with
    - **and the armour TYPE on that line is the one the creep counts as right
      now**, not the one it was authored with. One tower alters it for a few
      seconds and the line says so for as long as it holds, so the word next to
      the number and the debuff square underneath can never disagree
    - **the ATTACK line answers the same way**: the speed the tower is swinging
      at right now and the distance it is reaching right now, not the two
      figures on its stats file. A technology disc lends a tower speed, reach
      or damage, and a creep aura takes speed and damage away - all of it lands
      on these lines, and nothing in the game changes either of those two
      permanently, so on that line every point of difference is tinted
      - what is EARNED is repeated on the end and what is REACHING the tower is
        not, which is the whole difference between them: growth belongs to the
        tower and follows it, and an aura is a fact about where it is standing
    - **a PERMANENT change is folded into the plain number and a TEMPORARY one
      is written beside it, tinted.** Green for something helping the unit, red
      for something hurting it, on every stat line the panel draws - armour,
      damage, attack speed, reach
      - the split is what the player is actually asking. What is permanent IS
        the unit's number now, and belongs in the figure they read as the
        unit: damage an Alchemist has devoured, armour a Divineshroom has eaten
        for good, armour a packmate has handed over for the rest of a creep's
        life, a creep's own trait. Drawing one of those as a change would say
        something is about to wear off that never will
      - what is temporary is a fact about where the unit is STANDING or about
        what somebody has just done to it, and a player deciding whether to
        step out of it, sell the thing granting it or wait for it to pass needs
        to see exactly how much of the number goes with it
      - **a technology disc counts as temporary** even though nothing ever
        expires it, on that same reading: it stands beside the tower rather
        than being part of it, and selling one takes its points away
      - the base and the change always add back up to what the unit really is,
        because the base is worked out by taking the change OFF the whole
        answer rather than by rebuilding it from the permanent half
      - all four lines are re-read while the panel is open rather than written
        once, because a disc going up beside a tower moves them while the
        player is looking straight at the number
    - **hovering the armour line says what those points are worth**, as the
      percentage of a hit they take off. The curve has diminishing returns in
      it, so no player could work that out from the number itself, and negative
      armour reads as a MINUS reduction rather than as an increase - one scale
      running through zero rather than two rules meeting at it
  - Below those, attack speed and range, on a line that is left out entirely
    for anything that cannot attack
  - **and MOVEMENT SPEED, for the things that move** - the creeps and the
    builder - left out for every tower on the same grounds the damage line is
    left out for a creep
    - nothing in the game changes a creep's speed for good, so the plain figure
      is always its authored one and every point of difference is tinted. A
      creep crawling under four towers' worth of chill is the loudest case of a
      temporary change in the game, and the line is where a player reads how
      much of it is theirs
  - **A SHIELD is drawn as the second resource**, in the bar and the line under
    the portrait, in the teal an RTS has drawn a shield in for thirty years. It
    wins over a pool where a unit has both, because a unit behind a shield is
    not dying and that is the more important thing about it
  - **While the tower is on a clock, those stat lines give way to the
    countdown**: the picture of what the job is about, what it is called, the
    seconds left, and a bar
    - the panel says one thing at a time. A tower two seconds from being sold
      is not a tower whose attack speed anybody is reading
    - the picture is what the job is ABOUT rather than the tower it is
      happening to - the Sell button for a sale, and what a morph is turning
      into for an upgrade or a return, on the same grounds the rising model
      shows what is being bought
    - the name is the tower's own and stays where it is. What is counting down
      is happening TO the thing the panel is already describing
    - the seconds round UP, so a countdown never shows a 0 that is then waited
      on
  - A command card grid on the right holds that unit's available commands
    - 4 squares across by 3 down. Most units leave most of it empty, which is
      the price of the send building and the build menu having room
  - A slot carries its ability's hotkey letter small in the top left corner,
    leaving the middle of the slot to the icon
  - A PASSIVE shows the picture of the thing it belongs to - an elemental
    tower's named ability draws that tower - because a passive is a rule rather
    than a thing and has no art of its own. An iconless square is a hole a
    player learns to skip over
  - A passive draws no letter and cannot be pressed, but it still OCCUPIES the
    square that letter is bound to, so every passive on a card costs a key
  - **Elemental towers all put their named ability in the SAME square**, so
    where to read what a tower does is learned once and never moves whichever
    element or tier is selected. It is a square worth a hotkey and spending it
    on something unpressable is the price of that
  - **One square on every tower's card holds SHOW RANGES**, the readout that
    briefly draws that tower's attack range and its ability radii at once. The
    same square on every tower, Basic and elemental alike, so the question is
    asked the same way whatever is selected - see Towers and attacking
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
  - That sweep is the ONLY mark for a square that cannot be pressed, and
    nothing dims the icon. A square with no charge coming but no way to be used
    either - a tower there is no gold for, an upgrade whose technology is
    missing - is covered whole, as a wait that has not started. A passive is
    never covered, since it is only ever read
  - A square waiting on a one-off delay before it exists at all counts the
    seconds left down across its middle. A creep's start delay is the one thing
    that does this today
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
  - it also has ONE key of its own, which opens and closes it and is drawn on
    the button that does the same job. It is not read off a square, because the
    screen is not a unit and has no card to sit on, and like the other keys of
    their own it can be rebound
  - THE SELECTION ALWAYS WINS A KEY, this one included. A letter the selected
    unit's card answers stays that unit's, whether the screen is open or shut,
    so a screen left open can never quietly change what a key does and building
    and researching never become mutually exclusive. Only what no card claims
    reaches a square, and with nothing selected every letter is the screen's
  - so a square whose letter the selection has taken is reached with the mouse
    for as long as that selection lasts, and Escape closes the screen whatever
    is selected
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
  - What a player is CALLED there is the match's own answer. Ordinarily it is
    the display name; an ANONYMOUS match names them by their colour instead,
    which is a match setting the host chooses in the lobby. See Match settings
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
  - NOT BUILT: any way to change that scheme in game. The options menu exists
    but carries no minimap page, so it is set in the presentation config
  - the COLOURS themselves are chosen in the lobby and travel with the match.
    See Player colours below
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
  - Edge panning, which is a PLAYER SETTING on the options screen rather than
    authored data: it moves the view without being asked to, so whoever is
    sitting at the machine decides whether it does. Only how wide the edge
    strip is stays in the camera config
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
  - **An ability that sends a creep backwards is a different rule**, and mixing
    the two up costs the whole effect. Being built on asks "where is the last
    place I fitted" and walks the route for it. An ability that takes a creep's
    PROGRESS already knows where it is sending it: the spot is remembered when
    the creep is marked and it goes back to exactly that, so what it loses is
    exactly the ground it covered while the effect ran
    - walking the route for that one would send the creep to its own feet,
      since every point it has just walked is still clear
    - the remembered spot is checked before the creep is put on it, and the
      nearest gap stands in if something has been built there meanwhile
    - it works on a FLYER, which walking the route cannot: a flyer records no
      route at all
  - **a creep shut out of an effect stays shut out in ONE unbroken stretch**,
    covering the effect running and the cooldown after it. Applying the two
    halves separately leaves a seam exactly one tick wide, where the creep is
    briefly free between the effect ending and the cooldown starting - and a
    second tower firing into that tick marks a creep that is about to be moved,
    which then collects to a point it is no longer near and throws it the wrong
    way
    - the seam is not theoretical. The two counters are the same number
      advanced by different nodes, so they land on the same tick and which
      moves first is tree order - a coin flip, every time
- **A TECHNOLOGY DISC IS NOT A WALL.** Creeps walk straight over one, so a disc
  changes nothing about the shape of a maze - it only claims its square against
  anything else being built there. See Technology discs
  - which means no arrangement of discs can ever seal an area, and placing one
    is never refused for the route: the check that a path still exists is not
    even run for a footprint that does not block
  - and a creep standing where a disc goes up is left exactly where it is,
    where a tower would have set it back along its route
- Path recalculation was a known performance concern, settled by giving each area
  one shared route rather than pathing every creep separately

# Towers and attacking
- A tower attacks by itself, and can also be ORDERED onto one specific creep
  - The order is an ability on the card, and also a plain click on a creep -
    either button - whenever the selection holds anything that can shoot it
  - A creep clicked while nothing that can attack is selected still just
    selects, so reading a creep never stops working
- **The attack order is an attack-MOVE**, and takes either a unit or a patch
  of ground - whichever the click landed on
  - aimed at a UNIT, anything that can walk closes the distance and then kills
    it. Nothing else is worth stopping for on the way: the player named that
    one
  - aimed at the GROUND, the unit walks there and attacks whatever comes into
    reach. **What it finds it COMMITS to**, exactly as if the player had
    clicked that creep: it chases it and stays on it until it is dead, or
    until it is no longer something that can be aimed at - walked off the end
    of the maze, say. Only then does the walk resume
  - without that commitment the walk starts again the moment the creep steps
    out of reach, so the unit lands one hit, watches it leave and carries on.
    A chain behind it waits the whole time: the next order does not start
    until the fight is over AND the point has been reached
  - a TOWER cannot walk, so for a tower the movement half simply does not
    happen and what is left is the plain "shoot that one" order it always had.
    Aiming one at the floor does nothing
  - an attack aimed at the ground is confirmed with the ordinary move marker,
    because an attack-move is a walk with a temper. Aimed at a unit it is
    confirmed on that unit, below
  - Arming the ability draws the reach of every selected unit on the ground, as
    ONE shape rather than a circle each: overlapping ranges are painted once,
    so two towers covering the same ground never darken it. Each tower's own
    outline is still drawn inside the union, so it stays clear which tower
    reaches where
  - Left click on a creep gives the order, right click or Escape cancels, and a
    left click on anything else cancels without ordering
  - A unit that could never be aimed at that target at all - a tower pointed
    at another tower - refuses the order QUIETLY and carries on with whatever
    it was already shooting. That is what makes the order safe to give to a
    whole selection: the ones that can help take it, the rest are untouched
  - **An order is HELD until its target is dead**, or until that target stops
    being something this unit could be aimed at. Out of range is neither of
    those: the order stands, the unit shoots whatever it CAN reach meanwhile,
    and it switches back the moment the named one is reachable again
  - That is what makes an attack worth chaining on a tower: "shoot that one
    after this one" is a task with a lifetime rather than an instruction that
    is either obeyed or thrown away on the spot
  - Ordering never turns the automatic behaviour off. It only overrides which
    creep is current whenever the ordered one can actually be hit
- A range circle FOLLOWS the unit it belongs to. Redundant for a tower, which
  never moves, and the whole point for anything that walks: a creep or the
  builder leaves a circle nailed to the ground within a second of being given
  an order
- A reach that answers nothing is not drawn at all, and the builder's hammer is
  the case: a melee swing barely wider than the unit itself, on a unit that
  walks, is a ring on its own feet. Whether a reach is worth showing is
  authored on that attack, since nothing else can know
- **Every tower can be asked what it reaches**, on its own square on every
  tower's card
  - It draws the reach and then takes it away again after a few seconds. A
    reading rather than a toggle: leaving it switched on would mean learning to
    switch it off, and a maze under a pile of circles is a maze the creeps
    cannot be seen in
  - What it draws is the tower's ATTACK range in the usual colour, and every
    ABILITY range it has in a second one. One second colour for all of them,
    because no tower in the roster carries more than one - a third would be a
    colour nobody could learn
  - Which abilities have a range worth drawing is HAND PICKED, and the test is
    whether the radius decides where the tower goes: an aura, a healing reach,
    how far a Void tower spreads, how far an Alchemist's overflow carries
  - **An attack's SPLASH is not one of them.** It lands where the shot lands,
    so a ring around the tower would answer a different question
  - It draws the whole SELECTION, exactly as aiming an attack does, and obeys
    the same union rule - two towers covering the same ground never darken it
  - **Where circles overlap, the SMALLEST one owns the colour of that ground**,
    whichever kind it is. So an aura sitting inside a longer reach reads as its
    own disc rather than disappearing into it, and with several towers selected
    the innermost thing covering a patch is always the thing naming it. Two
    circles of exactly the same size go to the ability, since the attack range
    is already written on the panel
  - Outlines are drawn on top of every fill, so an edge stays readable wherever
    it crosses another circle
  - It is FEEDBACK and never leaves the machine, like the selection, the build
    ghost and the range the attack order draws
- An attack order is confirmed on the TARGET, not on the ground
  - A red ring blinks on the creep for about a second and a half, then goes
  - It rides the creep and dies with it, so it can never point at a corpse
  - The move order marker is deliberately NOT shown for an attack: what was
    chosen is the creep, and a marker on the floor would answer a different
    question
- Changing the SELECTION ends whatever was being aimed at the old one, along
  with any circles drawn for it. Both belonged to units the player has stopped
  looking at, and a card left on its lone Cancel for a unit that armed nothing
  is a dead square
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
- **CLOSE ONCE, THEN HOLD.** A unit sent at a target walks straight at it, and
  from the moment it is in reach it stays put - through the windup and the whole
  cooldown behind it - setting off after the creep again only when the next
  attack is ready
  - the approach is never gated on the cooldown. The unit has to be in reach
    anyway, arriving early costs nothing anybody would want back, and an order
    that left it standing for a whole attack period would read as an order that
    never registered
  - what IS refused is TRAILING: once it has arrived, following a creep through
    a cooldown it can do nothing with buys nothing and quietly takes the kiting
    out of the player's hands. Hit and run is the PLAYER's to order, which is
    what makes it a skill
  - re-issuing the order on the creep it is ALREADY standing at does not hand
    the walk back. Otherwise the rule would be undone by clicking twice, and
    the fastest player would be the one who spams the button
  - a DIFFERENT creep is a different quarry and gets its own approach, at once,
    however long the cooldown has left
  - it changes nothing for a tower, which never moves, or for an attacker creep
    marching on a tower that cannot run away. The builder is the unit it is
    actually about
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
  - **a unit that WALKS drops its swing the moment a new order arrives**, and
    that is the one place the commitment above gives way. Told to move, to
    build or to fight something else mid-windup, it abandons the blow at once
    and the animation goes back to rest rather than finishing its arc
    - the two rules answer different questions. A tower may not be RETARGETED
      mid-swing because the animation would land somewhere it never played;
      being ordered elsewhere entirely is not a retarget, it is the player
      saying the fight is over
    - it is only for what walks. Nothing a player can order a tower to do is a
      reason to take a swing back, and a tower is never in the player's way
    - the cooldown is not handed back here either, so spamming orders at a
      unit is not a way to make it attack faster
    - SHIFT-queueing does not cancel anything: a queued order is what to do
      NEXT, and the swing in the air is still what is happening now
  - a windup is authored only where there is an animation to fill it. A delay
    with nothing playing in it is one a player cannot see the reason for

**EVERY REACH IN THE GAME IS A MULTIPLE OF A QUARTER CELL**, and every reach
is SHOWN as a bare number with no unit written after it.

- A reach is any distance a player can measure on the ground: an attack range,
  a splash, an aura, a blast, how far an ability throws something. Movement
  speed is the same measure per second and follows the same rule, so the whole
  creep roster moves between 1.25 and 4.
- The quarter is what makes those numbers comparable. The source game states
  its distances in Warcraft III map units and 128 of them make a cell, so a
  straight conversion gives 2.34, 4.69, 7.03, 9.77 - a wall of figures nobody
  can hold in their head or tell apart. Rounded, a player learns a handful of
  values and can compare any two towers at a glance.
- It costs up to an eighth of a cell against the source figure, which is less
  than the width of a creep. `unit_data.md` 3 has the conversion and the one
  place in the code it happens.
- **The word "cell" is never written next to one.** The number is the reach; a
  unit repeated on every line of every tooltip is noise. The grid still calls
  its squares cells in this document and in the source, which is why anything
  a player reads says SQUARE for those.

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
  - Default priority is the creep NEAREST the tower
  - Nearest is the only priority measured FROM THE TOWER. Every other one ranks
    the creeps themselves, so a row of towers coming off cooldown in the same
    tick would all pick the same creep and empty into it while the rest of the
    wave walked past. Nearest spreads them across a wave on its own, with
    nothing coordinating them
  - A SKITTERING creep is considered only once nothing else is in range at all,
    whatever the priority says. That is a priority and not an immunity: a tower
    with nothing else to shoot shoots it, and an attack ORDER lands on it
    normally, so one can always be picked out by hand
  - Other priorities exist in the data - first in line, strongest, weakest - and
    no tower uses them yet. FIRST measures along the route that creep actually
    committed to, so one that took the long way round counts as being where it
    really is
- A tower still going up cannot attack. One being sold still can, since the
  sale can be called off and it is still standing
- A DESTROYED tower leaves RUBBLE on its cells for a few seconds
  - the cells go back to being walkable immediately: a destroyed tower stops
    being a wall the moment it falls. Only BUILDING there waits
  - which is what stops an attacker creep's work being undone the instant it
    finishes, and it is the only thing rubble does
  - it is DRAWN, as a smoking patch over the square for exactly as long as the
    square refuses a build, so a refused placement is never unexplained. The
    patch is presentation and decides nothing: it is spawned beside the rule
    rather than by it, and a dedicated server draws none
  - selling a tower leaves none, so a player can never lock their own cells
  - NOT REPLICATED: rubble is marked by the authority, which is the only
    machine that knows a tower was destroyed rather than sold. A client's build
    ghost can therefore read green over a cell the server refuses for those few
    seconds. See multiplayer.md
- How the hit reaches the target is one of three kinds, never more than one
  - Instant: the damage lands the same moment the tower attacks, with or
    without a visual. A tower can be a spinning blade that simply hurts what
    stands next to it
  - Projectile: a projectile is spawned, flies to the target and deals its
    damage on impact. It carries its own speed and flight arc
  - A projectile homes, so a creep cannot outwalk a shot already aimed at it
  - A target that dies mid flight does not waste the shot: it lands where that
    creep last stood, so a splash still catches the crowd around it
  - Selling a tower never deletes a shot already in the air
  - SOME shots are CALLED DOWN rather than fired. The projectile is spawned
    above and to one side of the creep instead of at the tower's muzzle, high
    enough to be off the top of the screen, and its whole flight is the dive
    onto the target
    - it is still an ordinary projectile in every other way: it homes, it takes
      real time to arrive, and its damage lands when it does
    - the tower it came from is not on the line at all, which is the point. A
      tower whose damage comes out of the SKY should not look like it is aiming
      along the ground, and the same rule already decides what such a tower
      LOOKS like - see Presentation
    - it always falls from the same direction, whichever tower called it and
      wherever that tower stands, so a player learns to read one shape
  - Pierce: the third kind, and the only shot in the game that does NOT home. It
    leaves along the line to wherever the target stood, damages every creep it
    passes through, and expires after a fixed distance
    - **it can miss.** The creep it was aimed at can walk out of the line and
      take nothing, and a creep that walks INTO the line after the shot left is
      hit anyway. Nothing else in the game works that way and that is the point
      of it existing as its own kind rather than as a setting on a projectile
    - the distance it flies is its own, NOT the tower's attack range, and is
      longer: the tower acquires a target inside its range and the shot carries
      on past it. What a player reads off a piercing shot is how far down the
      lane it reaches, so tying that to a targeting range would move it every
      time the range was retuned
    - the FIRST creep it touches is an ordinary hit and goes through the whole
      pipeline - the tower's ability, its on-hit effects, kill credit.
      Everything behind it takes what the shot did on its way past, and an
      ability may ramp that up per creep already passed and cap how many it goes
      through at all
    - it is not area damage. A pierce is a line of single targets, exactly as a
      multishot is a handful of them, so a creep that resists area damage gets
      no help from either
    - no physics: the shot is a point walking a line, and a creep is struck when
      it is close enough to the SEGMENT covered that tick. Testing the segment
      rather than the point is not optional at these speeds - a shot covers more
      than a creep's width in one tick and would step straight over it
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
    - a line pattern is INSTANT and is a different thing from a piercing shot,
      which covers the same ground over real time and can miss. An ability whose
      own attack pierces should be the shot rather than the pattern; the pattern
      is for an ability that reaches down a line the tower did not fire along
  - BURNING GROUND is what an attack leaves behind on the GROUND rather than on
    a creep: a patch that keeps damaging whatever stands in it, on its own
    clock, until it goes out
    - it is not a status effect. A status effect rides a creep and dies with
      it; this stays where it landed and catches whatever walks in afterwards,
      including creeps that were nowhere near the impact
    - its damage is a share of what the ATTACK dealt rather than a number of
      its own, so one authored rule covers every tier of a line and the patch
      can never drift out of step with the shot that lit it
    - its radius is measured off the attack's own splash and is a SHARE of it,
      so a fire can never be authored bigger than the blast that lit it. The
      share is deliberately well under one: the splash is instant and invisible
      and the fire is the only part drawn, so a patch at the full splash radius
      reads as the tower's whole area of effect - which it is not - and is the
      loudest thing on the field while it burns
    - the first tick lands a full interval after it catches, because the attack
      that lit it has already hit everything standing there
    - it stacks with splash rather than replacing it: the splash is what the
      impact did, the patch is what the ground does afterwards
  - STATUS EFFECTS are what an attack leaves BEHIND on a creep, and they are
    the creep's rather than the attack's. See Status effects below
- A DEBUFF LANDS ON EVERY CREEP THE ATTACK TOUCHED, and that is the one thing on
  this page that does not care how a creep was caught
  - the creep aimed at, every creep a multishot picked up alongside it, every
    creep the splash covered, and every creep a piercing shot went through: a
    tower that chills chills all of them, and one that eats armour eats all of
    theirs
  - because a debuff is stated PER CREEP. A tower whose blast covered six creeps
    and chilled one would be describing an attack nobody watching it could
    recognise, and it is why an armour-eating tower is worth putting in front of
    everything else at all
  - the DEBUFF is the whole of what spreads. Everything a tower's ability does
    that is measured per SHOT stays with the creep that was struck - damage the
    tower banks, health it steals back, a burst it sets off, a stun on the
    target it was aiming at - because paying those once per creep standing about
    would multiply a splash tower's ability by the size of the crowd
  - a technology disc lending a tower a chill or an armour bite follows the same
    rule, under its own separate cap. See Technology discs
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
  server as well as marked unavailable on the card - until the ordering player
  owns it
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
4. A handful of pieces of them are deliberately left out or approximated, and
they are written down here rather than being quietly dropped:

- **Aether Attunement's manual target** (Ultimate Spellslinger). The source lets
  a player set the attuned creep by hand on a shared 30 second cooldown; here
  the tower attunes to whatever it is currently shooting. The automatic half is
  what the source does anyway when nobody sets one
- **The technology sell refund.** `unit_data.md` 1.8 gives a technology tower a
  50% refund against a Basic tower's 60%. The refund share is one value shared
  by every building, so every tower currently refunds 60%. Splitting it is a
  rules change rather than content
- **Frostfire's per-tick slow** (Spellslinger line) is applied at its cap in one
  go rather than a step per tick of the burn, because nothing in the burn runs
  per tick. The depth reached is the same; the ramp to it is not
- **Frenzied Flames** (Ultimate Moonbeam) burns everything standing in the
  radius when the shot lands, rather than leaving a patch of ground alight for
  three seconds. The same damage over the same window, except that a creep
  walking INTO the flames afterwards is not caught. Ground effects DO exist now
  - the Moonbeam's own attack leaves one - so this is no longer waiting on
  machinery, only on somebody deciding it is worth the change

Every one of these is a decision to leave something out, and they stand.
Frenzied Flames is the only one whose blocker has since gone - ground effects
exist - so it is the one that could be built today if somebody decides it is
worth the change.

**Crystalized Light's mana drain used to be on this list and no longer is.** It
was deferred because creeps carried no mana at all; several of them do now, and
the Ultimate Crystal's lance takes it off every creep it passes that has a pool
to lose any from. See Status effects.

- The builder places FOUR towers: the three 10g Basic ones, and the **Elemental
  Core** at 200g. Everything else in the game is reached by upgrading one of
  those four, which is what keeps the build menu four buttons long however deep
  the roster grows
- The Core is the technology base tower and is deliberately weak. It is worth
  buying only for what it becomes
- It MORPHS into any element whose Basic technology its owner has researched,
  and the morph is FREE: the 200 gold was paid for the Core and stays sunk in
  that cell, so the sell refund is the same either side of the morph
- Its card carries the ten elements DIRECTLY, one square each, rather than
  behind a submenu. Choosing an element is the whole reason the Core exists and
  it should cost one press, not two
  - every element is shown, including the ones not researched, and each says
    which technology it is waiting on. A player has to be able to read what the
    ten of them would cost before buying any
  - ten elements plus Sell plus the held square fill the card, so the Core is
    the ONE tower whose Attack and Prioritize are not on it. Neither is lost:
    it still shoots on its own, and a right click still orders it onto a creep.
    A 200g tower that exists to be morphed is not one anybody aims by hand
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

# Tower auras
BUILT. A few towers affect everything standing near them rather than only what
they shoot.

- **A tower's aura and its attack are SEPARATE things.** A tower that carries an
  aura does its work through that and its attack is a plain attack; a tower
  without one puts the same kind of effect on what it hits instead. No tower
  does both, so what a player has to learn is which of the two a tower is
- **AN AURA DOES NOT LAND AT FULL STRENGTH.** It builds on a creep in equal
  steps and drains off again once nothing is holding it, so walking through the
  edge of one is worth a fraction of standing in the middle of it
  - a creep gains one step per tower per interval while it is inside the radius,
    and every effect that aura applies is scaled by how many steps it holds. At
    the top of the ladder the aura is doing exactly what it says it does
  - **THE STEP COUNT IS THE WHOLE MECHANIC.** An aura has one ladder and no
    clock of its own beside it: what it is doing to a creep is read off that
    count and restated on every beat, so it moves the instant a step lands or
    drains. An aura that ran a second ramp on top would leave the debuff row
    showing a full grip while the creep was barely touched, which is exactly
    what the Sludge Monstrosity used to do
  - **standing in two of the same aura fills it twice as fast.** Each tower
    lands its own step on its own beat, so massing a support tower buys
    something real rather than being wasted on an effect that does not stack
    - and every TIER of one line counts as the same aura: a Lesser and an
      Ultimate over one creep fill one ladder between them, and what they do
      with it is the stronger of the two rather than both. Same rule the slows
      follow, and the same authored key
  - two DIFFERENT auras never interfere. Each is its own grip on the creep
  - once nothing has reached a creep for a short window, it starts losing steps
    on a clock. The grip LINGERS: crossing a gap between two towers, or briefly
    outrunning one, does not send the creep back to nothing
  - a creep already at full still counts as gripped, so an aura that can give it
    nothing more still keeps it from draining
  - the numbers are one set shared by every aura in the game, in GameConfig, so
    this reads as one mechanic a player learns once rather than three that
    happen to be similar
- **An aura that lengthens slows does it to slows as they LAND**, never by
  topping up the ones already running. Reaching in to add seconds to a running
  chill several times a second would make every slow on anything standing in the
  aura permanent

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
  - each PATH keeps its own cap, which is what "up to 40%" means at all. Every
    tier of one upgrade line shares it, so a Lesser and an Ultimate of the same
    line are ONE slow climbing to whichever of their caps is higher - upgrading
    a line replaces its slow rather than stacking a second copy of it
  - slows from DIFFERENT paths MULTIPLY. Two lines each taking 40% leave a
    creep at 36% speed, not 60% and not 20%: each takes its share of what is
    left, so piling more on always helps and never stops the creep dead
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
  - the CEILING is on the creep with it. Ten stacks is ten stacks from any
    tower of the line, never ten per tower, and a hit landing on a creep that
    is already full adds nothing - which matters because the tower that filled
    it may still be inside its own cooldown before it can set it off
- **A mana drain** takes points off a creep's own pool per second, for a
  window. The only thing in the game that reaches a creep's mana, and the only
  status effect that does nothing at all to most of the roster: a creep whose
  traits do not run on a pool has none to lose and is refused it outright,
  rather than carrying a debuff that is doing nothing
  - the BEST rate wins rather than the sum, the way a heal and a haste do. It
    is a state the creep is in - its regeneration crystalized - rather than
    damage arriving, so two towers holding it there hold it once
  - it NETS against whatever is filling the pool rather than replacing it, so a
    creep that regenerates faster than it is drained still fills, only slower.
    See Mana
- An **armour type** can be altered for a few seconds, once per type per creep
  - WHICH type is a choice the player makes per tower, cycled on the command
    card, and the tower says what it is currently set to. There is a default,
    so a tower nobody has pressed still does something
- Tiers 3 and 4 brought four more, and they are the first ones a CREEP applies
  to itself or to a packmate rather than a tower applying them to a creep. They
  live in the same set because what the panel is answering is "what is on this
  creep", and a row that only listed the bad half would answer a different
  question
  - a **SHIELD** is a pool of damage standing in front of the health, spent
    before any of it reaches the bar. It is not a resistance and must not be
    folded in with them: it runs LAST, after every ratio and every block, or a
    creep behind one would take a share of every hit forever instead of none of
    the first few. Sources add
  - a **WARD** is a window in which the creep takes nothing at all - no damage,
    and nothing a tower would leave on it either: no slow, no stun, no eaten
    armour, no poison and no aura's grip. Not the invulnerable armour type,
    which is permanent and also refuses heals - a warded creep still
    regenerates, is still shot at, is still hasted by its packmates and still
    takes a shield
    - what is REFUSED is what a tower tries to APPLY while the window runs.
      Anything already on the creep when the ward landed goes on running and
      counting down; a window that also swept the creep clean would be worth
      more the harder it had just been hit
  - a **HASTE** is the mirror of a chill and is kept apart from one, so a creep
    that is both hurried and slowed ends up between the two rather than at
    whichever landed last
  - **MENDING** is healing over a window. The best rate wins rather than the
    sum, the same rule auras follow
- Armour can also be GIVEN permanently, and given BACK. One trait hands a
  packmate two points for the rest of its life; another returns what a tower
  has eaten, never past what the creep started with. The gift and the erosion
  are kept apart, so a floor meant for one cannot clamp the other
- Every "once every N seconds" rule in the game is one immunity key with a
  countdown, in one place, rather than a timer per effect
- A creep can RESIST what a tower leaves on it, in two ways that are separate
  and do not move together
  - a share of every harmful effect's DURATION, which is one number applied to
    all of them - a stun, a burn, an amplification, eaten armour - rather than
    to whichever ones somebody remembered
    - **a SLOW's clock is a SEPARATE number, and deliberately.** The source
      states the two apart and hands them to different creeps: what resists
      spells shortens spell windows and does nothing at all to a slow, and one
      trait alone shortens a slow's. One number for both charged a
      spell-resistant creep twice for a single trait - once in how far a slow
      went and once in how long it lasted - and left it walking through a maze
      of chill towers untouched
    - and a slow an AURA SUSTAINS is exempt from even that. An aura re-states
      its slow on its own beat, so its window is a hold rather than a clock:
      cutting it short does not end the slow sooner, it drops the slow between
      beats and leaves the one creep that shortens slows immune to every aura
      in the game. What an aura holds on a creep ends when the creep walks out
      of it and by nothing else
  - a share of a slow's MAGNITUDE, which blunts the slow and its own cap
    together. Blunting only what lands would leave the cap where it was and a
    resistant creep would still reach the full slow, just later, which is the
    opposite of what resisting a slow means
    - and a FURTHER share for a COLD slow on top of it, which is a separate
      claim and a separate number. "Cannot be slowed" is about every slow in
      the game; "50% immune to movement chill" is about FROST, and a creep
      carrying only the second is ground down by a Sludge Monstrosity's aura
      and held by a Titan Vault exactly as anything else is. Frost is an Ice
      tower and an Ice disc, and nothing else
  - a CEILING on how far a slow may ever go, whatever has piled up. That is a
    different thing to blunting each chill: a resistance still lets four towers
    add up to something large, and a ceiling refuses the total past a line
  - a CEILING on how long any harmful effect may run, whatever it asked for.
    One trait states both a share and a maximum, and a share alone cannot say
    the second half
  - all of them are read off the creep's own traits ONCE, when something first
    touches it, since a creep cannot gain or lose a trait while it walks
- NOT REPLICATED: a client is not told what is on a creep. It sees the creep
  where the server puts it, which is most of what a slow or a stun looks like,
  and the armour figure on a creep's panel is that creep's own. See
  `multiplayer.md`
- **Nor is it told how far through a tower's own COOLDOWN it is.** A repeating
  ability's clock lives on the tower and is advanced by the server, so on a
  client the fill over that square does not move. The ability itself is
  correct - it is the server's to run - and what is missing is only the readout
  - the honest fixes are a field on the wire or moving the clock onto the match
    clock so both machines can compute it, and neither is worth doing for one
    square until somebody is actually bothered by it

**A TOWER CAN CARRY EFFECTS TOO, and tiers 3 and 4 are where that starts.**
BUILT. Its own much smaller set, and it should stay small: a creep is the thing
this game applies effects to and a tower is on the receiving end of a handful.
  - a CURSE on its attack speed, left by a creep as that creep dies
  - an AURA weakening its attack damage, re-applied every tick a creep is in
    range, so a tower restores itself a moment after the creep walks on
  - the "not again for N seconds" gates, so that draining one tower twice in
    quick succession is refused whichever creep does it
  - created on the first one applied and dropped the moment the last runs out,
    exactly as a creep's set is, so an untouched tower costs nothing

# Mana
BUILT. A TOWER thing first and mostly, and now a few CREEPS have it too.

- Nearly every elemental ability is "fill up by attacking, then spend the lot",
  so mana is the clock most of the roster runs on
- It is filled by REGENERATION, by ATTACKING, or by both, and each is the
  tower's own passive rather than a property of the tower
- One tower is built FULL and can never regain a point - the Moonbeam line,
  whose whole design is being at its strongest the moment it is placed
- One tower lowers its own MAXIMUM as it fires, and pulls its neighbours' down
  with it when that bottoms out - the Ultimate Orb Keeper
- Mana carries across an upgrade, along with anything else a tower's ability had
  banked: an Apprentice keeps its mana when it becomes a Sorcerer, and an
  Alchemist keeps the damage it has eaten. A tier that authors a starting share
  of its own overrides that, which is how the Moonbeam is built full
- One line uses its bar as a CLOCK rather than as a cost - Void's base pair.
  The bar fills, and the moment it is full the ability fires; nothing is spent
  and the bar never resets, so a tower that has used its one chance sits at
  full for the rest of the match
  - which means its bar is not drawn any more, since a full one never is. A
    Void tower still counting down shows a filling bar and one that is finished
    shows nothing, so the bar appearing IS the thing pending. What it costs is
    that a Void tower which has already grown looks the same as one that never
    had mana at all
  - **and the chance is spent whether or not it lands.** A Void tower whose bar
    fills with nothing it can take standing near it has missed, and does not
    sit waiting for a neighbour to be built later. Where one is placed is a
    real decision rather than something that sorts itself out eventually
- Only towers that use any show a mana line on the panel - and a tower whose
  ability banks a count of its own shows that instead, since the two share one
  bar and one line. See the second-resource rules under Presentation
- A CREEP has mana only when one of its traits runs on a pool, which is a
  handful of them across the roster and none at all in tier 1
  - the pool is the creep's and the rule is the trait's: what fills it, what
    happens when it is full, and what it costs are the trait's business
  - what fills it is the trait's answer and there are three of them. Most bank
    a point per HIT TAKEN and spend the lot at a threshold, which is the shape
    the first one set. Some REGENERATE on a clock instead. One starts FULL and
    drains, so its pool is a timer counting down rather than a cost being saved
    - no creep fills a pool by attacking, which is the one route open to a tower
    and closed to a creep
  - it shows on the unit panel exactly as a tower's does, and nowhere else. A
    creep carries no worldspace mana bar - a pack of three walking down a lane
    under a row of blue lines is noise where one tower's bar is information


# Towers that spread
BUILT. One element converts other towers into copies of itself, free.

- A CONVERSION is not an upgrade and not a purchase. No gold changes hands, no
  countdown runs, and the tower being converted is not the one whose ability did
  it - somebody's tower simply becomes a different tower where it stands
  - the gold sunk into it does NOT change either. A 10g tower that becomes a
    200g one still has 10g in it and still refunds a share of 10g, or the line
    would print gold through the sell button
  - **nothing is handed down.** What stands there afterwards starts at zero,
    with none of the mana or the banked state the tower it replaced had. That is
    the difference from an upgrade, which IS the same tower one tier on: a
    converted tower is a new one, and a converter that passed on its own full
    bar would hand its replacement a free second use of the same ability
- WHICH tower is taken is decided by price first and distance second: the
  cheapest thing in reach, and the nearest of those where several tie
  - price first because the cheap rungs are what the line is meant to eat -
    taking the cheapest tower on the field costs its owner almost nothing, and
    taking a real one costs real value
  - what may be taken at all is an authored list per ability, so a tower is safe
    from conversion unless something explicitly names its type. No elemental
    tower is on any list
  - a tower still going up, being sold, or mid-upgrade is never taken
- WHEN it happens is the ability's own business, and the two that exist answer
  it differently: one fills a mana bar once and spends the chance on whatever is
  standing there, the other runs on a repeating clock and simply tries again

# A tower with two named abilities
BUILT, on one tower.

- Nearly every tower has exactly one named ability and it claims one square. A
  tower whose two halves are paid for DIFFERENTLY needs two, because a square is
  the only place the game can show a wait
- the second square sits directly beside the first, so a player who has learned
  where to read what a tower does finds its other half without hunting
- a repeating cooldown is drawn as a fill sweeping off that square, which is the
  same mark every other wait in the game uses. It is the ability's whole
  readout: there is no number and no bar for it anywhere else

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
- So are the technology DISCS, which are a separate thing from the towers and
  ask for technology in a different unit: a COUNT rather than a named one. See
  Technology discs below

# Technology discs
BUILT.

The roster, the prices, the technology requirements and the ten effects are in
`unit_data.md` section 5. This says how the system behaves.

- **A disc is a building that creeps WALK OVER.** That is the whole design of
  the thing and everything else here follows from it
  - it claims its square against anything else being built there, exactly as a
    tower does, and it changes nothing at all about how a creep moves. The
    route sweep does not see it, a creep standing where one goes up is left
    alone, and placing one is never refused for want of a path
  - so a disc goes in the holes a maze ALREADY HAS rather than making new ones,
    and the shape of a maze and what is standing in it become two decisions
    instead of one. That is what a disc is for
- **It cannot attack and cannot BE attacked.** Armour type Invulnerable, which
  is the absence of damage rather than a resistance to it, and it carries no
  attack at all - so its card shows neither Attack nor Prioritize
  - the two halves together make a disc a square an attacker creep can do
    nothing with. It cannot destroy one, and it was never blocked by one
- **The BASE disc is bought and does nothing.** It needs no technology, it is
  available from the first second of a match, and it has no effect whatsoever
  until it is morphed into an element
  - so the price of the base disc is the price of the SQUARE, and the elements
    above it are what that square is eventually worth
- **An element is a free morph, and the two tiers above it are bought.** The
  same shape the Elemental Core has, and reached the same way: the base disc
  carries all ten elements on its own card, on the same ten squares the Core
  carries its own, so the letters that choose an element are one set of letters
  in the whole game
- **Technology is asked as a COUNT, not as a named one.** This is the one place
  in the game where it is
  - the element morph wants that element's Basic technology, which is a single
    id like every tower's - but the two upgrades above it want TWO OF THE THREE
    and then ALL THREE, and no single id means either
  - so a disc morph names the ELEMENT and how many of it are needed, and the
    count is walked at the moment the button is drawn. See `unit_data.md` 5.1
- **A player may own only ONE of each Ultimate disc.** The disc half of "you
  cannot fill the whole maze with the best thing"
  - counted over that player's own area rather than remembered, so a disc going
    away by any road at all - sold, morphed down, morphed up - is counted right
    without anything having to be told
  - a morph already RUNNING counts. Two started in the same second would
    otherwise both be allowed and both finish
- **Morphing back down takes longer than anything else in the game.** A disc
  goes back to a bare base disc, keeps its square for the whole countdown, and
  hands back the sell share of everything spent above the base
  - deliberately slower than a Return to Core, and it is the source game's own
    decision rather than this project's: swapping a disc on the fly to answer
    an incoming send is exactly what the wait is there to make expensive
  - the base disc's own gold stays sunk in the square, exactly as the Core's
    does, so the refund reads the same either side of the morph

## What a disc does
- Eight of the ten are AURAS reaching the friendly TOWERS around them, and two
  are ON-STEP triggers firing on the creeps standing on the disc itself
  - the on-step half only exists because a disc is walkable. It is the clearest
    case of the rule paying for itself
- An aura is re-granted on a slow beat and every grant EXPIRES on its own, so
  nothing ever has to take one away. A disc that is sold, morphed or built just
  out of reach simply stops calling, and what it was lending is gone a fraction
  of a second later
- **Where two discs of the same kind overlap, the STRONGEST wins** and the
  weaker one is worth nothing at all there. Two Ultimate Holy discs are worth
  one, and a weak disc can never drag a strong one down - which is a rule the
  source game had to fix as a bug, and is here a property of how a boon is
  stored rather than something any disc knows about
- An aura's radius is one of the hand-picked ranges worth drawing on the
  ground, on the test under Presentation: it is the number that decides where
  the disc goes, which is the whole of what a disc is. An on-step disc draws
  nothing, because its reach is the square it is already standing on
- **What a disc lends is READABLE on the tower it lends it to**, not only on
  the disc. The tower's own panel shows the speed, reach, damage and armour it
  has right now, and the range circle it draws - whether from Show Ranges or
  from an attack order being aimed - is the reach it really covers
  - which matters more here than anywhere else in the game, because a disc's
    whole value is what it does to something ELSE. A player who cannot see the
    difference on the tower cannot tell whether the disc was worth its square
  - the BUILD and UPGRADE cards are the deliberate exception and still quote
    the plain numbers: those describe a tower that is not standing yet, and a
    disc that is reaching the cell today may be gone by the time it is

## What a disc looks like
- **It has no model at all.** A disc is painted onto the floor and nothing
  stands up out of it, which is the one thing a player must never have to look
  twice at: a tower stands up, a disc lies flat, and nothing else in the game
  does either
- **It is drawn as THREE FLAT LAYERS**, and each answers exactly one question
  - the FOUNDATION is the same square patch every tower stands on, unchanged
    and shared. It says a BUILDING is here and that this square is claimed, and
    it says it in the same words a tower does - which is right, because that is
    the one thing the two have in common
  - the PLATE is a round worked disc set into that square, the same on every
    one of them. It says the building is a DISC
  - the GLYPH is a coloured circle in the middle. It says which ELEMENT and
    which TIER, and nothing else in the roster says either
  - **round on square is the whole trick.** The foundation and the plate are
    the same stone and must be, because colour belongs to the elements - so
    what separates them is that one is a square patch of ground and the other
    is a machined circle sitting on it. That reads from directly overhead at
    any zoom, and the square shows at every corner so the two never merge
- **The element is the COLOUR of that circle and nothing else.** One shape for
  all ten
  - an earlier cut gave each element the side count its towers are built on, so
    the roster would answer on two axes the way the towers do. It was dropped:
    a disc is the one thing in the game whose whole job is to be read in
    peripheral vision while the player is watching a creep wave, and counting
    sides at that size is something the eye will not do
  - what that costs is a second channel for a colourblind player, which the
    towers have and the discs now do not. If it turns out to matter the answer
    is not to bring the polygons back, but something read as fast as colour
- **The tier is how big that circle is, and nothing else.** A base disc has
  none at all, which is exactly right for something with no element that does
  nothing, and each upgrade grows it
  - one rule where a tower's ladder is six, because a flat circle has only the
    one thing to say everything with. A second rule laid over it would be
    fighting the first for the same pixels
  - the ceiling is set by the plate rather than by taste: the top rung has to
    leave a ring of stone showing, or the disc stops being a disc with a colour
    in it and becomes a coloured blob with nothing to read the size against
  - it also retired the one motion rule the discs had. Movement is reserved for
    the top rung everywhere else in the game, and a rotating circle is a still
    circle, so the Ultimate no longer turns. Nothing replaces it
- **An UPGRADE grows the circle and moves nothing else.** The foundation and
  the plate stay exactly where they are while the colour opens out of the
  middle of them, which is a picture of precisely what was bought
- **MORPHING BACK DOWN runs that backwards**: the circle shrinks away and
  nothing grows at all. What is being bought back is the empty square, so a
  countdown that grew anything would be a picture of the opposite trade
  - it is also the one morph that shows no preview of what is arriving. Every
    other one stands the new thing up and rises it, because the player is
    waiting for something they have not got yet; a disc morphing down is
    already standing on the foundation and the plate that will be left, so
    there is nothing to show them but the colour leaving
- A base disc being BUILT opens the whole thing out from a point instead, which
  is the right answer for it: nothing about it is arriving in the middle of
  something already standing there
  - rising is a thing a flat quad cannot be seen to do at all, which is why
    none of the three rises

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

# Aiming a Beastmaster
BUILT, on one line of towers.

The Beastmaster line is the only thing in the game that reaches DOWN a lane
rather than around a point: at full mana it sends a beast running from the tower
on a fixed heading, flattening every ground creep it passes through. Everything
about that is in `unit_data.md` 4.7 except the one thing a player decides.

- the heading is normally whatever the attack that filled the tower landed on,
  taken once at the moment of release and then committed to. The beast does not
  turn and does not home
- **linking** overrides it: the tower is aimed at one of the player's own
  towers, and from then on every beast runs that way whatever the tower happens
  to be shooting. That is what makes the line usable in a real maze, where the
  creep in front of a tower is rarely in the direction the lane runs
- only the DIRECTION is taken from the link. Distance has nothing to do with it,
  so there is no range on linking at all and the beast always runs its own
  distance. A tower on the far side of the map is a perfectly good aim
- aiming a Beastmaster at ITSELF is how the link is cleared. There is no second
  button: a tower aimed at itself has no direction to take, so it goes back to
  aiming at what it is shooting
- linking is on a cooldown, drawn as the same sweep every other wait uses, and
  the square lights while the tower is linked. Which way a Beastmaster faces is
  a decision about the shape of a maze rather than something to flick per wave
- the link is per tower, like Prioritize, and survives an upgrade: an upgrade is
  the same tower with a bigger beast

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
- A STANDING tower regenerates a share of its own maximum health every second,
  so a maze that survived a wave repairs itself between waves with nothing
  being pressed. See `unit_data.md` 1.4 for the share
  - a share rather than flat points, so one rule covers a roster whose health
    spans two orders of magnitude
  - it runs while a tower is being SOLD or UPGRADED, because both jobs leave it
    standing in the maze taking hits and both can be called off. It does not
    run while one is still going UP, where health is the construction ramp's
  - HEALTH IS A FRACTIONAL NUMBER, and this is why: one tick of regeneration on
    a cheap tower is a fraction of a point, and rounding each one away would
    leave it regenerating nothing at all
  - what the player is SHOWN is that number rounded UP, so a unit still
    standing never reads as 0 and a sliver regenerated reads as a point gained

# Creeps
- Creeps enter at the top and walk to the bottom
- Spawn position is randomised: random x across the width, random y within a margin at the very top
  - Every creep of a pack rolls its own position, so a pack arrives spread out
- Creeps carry a worldspace health bar like any damageable unit
- **Anything carrying a SHIELD carries a second bar just above that one**, teal
  and with a background behind it: the fill is what the shield still holds and
  the empty part is how much of it has already been spent
  - ABOVE the health bar rather than below, because a shield is what is spent
    first. A tower's second resource sits below its health bar for the mirror
    reason, and the two are then never confused at a glance
  - it is NOT the player's to switch off, unlike the health bar. A shield is the
    reason a unit is not dying, so one drawn with the health bar hidden would
    look like a creep nothing was hurting
  - it appears the moment a unit is shielded and disappears when the shield is
    gone, so nothing is drawn for the great majority that never carry one
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
  - Only ATTACKER creeps push each other apart. A pack of them crowds at a
    choke point rather than stacking into one body, and no two of them may ever
    stand inside each other at all - see the attacker rules below
  - Every other creep walks straight through its own kind. They are sent in
    packs and a lane holds a hundred of them, so nobody can read one body from
    two anyway, and shoving them apart pairwise cost more per tick than every
    other thing a creep does put together
  - Both halves are a number rather than a rule in code, so crowding can be
    switched back on for the whole roster without touching one
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
    - which is about FIRING and not about being ORDERED. A walking attacker
      may be aimed at anything at any moment - giving it the order is exactly
      what ends the walk, so the walk can never be the reason the order is
      refused. What still refuses one is having no working weapon at all
  - a COMMANDED walk reads the maze, the same way a creep walking to the end
    zone does: it takes a route round the towers rather than pressing into
    them, and it commits to that route until the cell it is walking into is
    the one that has been built in
    - so an attacker sent to a spot behind a wall goes round, and one sent
      into a pocket walks out of it. Without this it would lean on the nearest
      wall until it happened to knock a hole in it
    - it is the SAME pathfinding, asked for a spot the player pointed at
      instead of for the exit, and it is only planned again when that spot
      moves to another cell. An attack order re-aims its walk every tick and
      must not cost a search every tick
  - **an attacker keeps a ring of ground to itself and no other attacker may
    enter it**, which is the one place in the game where two units are held
    apart rather than merely nudged. The room it claims is a share of its own
    SELECTION CIRCLE, so what a player is looking at is what the creep takes up
    and a bigger attacker takes more of it
    - held every tick and wherever the tick left it, so it holds for one
      standing still as much as for one walking. A creep walked into is shoved
      out of the way rather than stood inside, which is what pushing looks like
      in any other RTS
    - only against other ATTACKERS, and only on its own layer: a pack walking
      underneath a flyer is not something either of them can feel
    - the share is a number rather than a rule in code, and zero switches the
      whole thing off and leaves the soft push every other creep has
  - a pack ordered onto ONE POINT piles up around it rather than stacking on
    it. Whoever gets there first holds the point and the rest stop where they
    are blocked, so the pack settles outwards a ring at a time instead of
    circling forever looking for a way in
    - that giving-up is for a point on the GROUND only. An attack order names a
      tower, and there is a whole ring of ground within reach of one, so a
      creep sent onto a tower keeps going and is shoved round the outside until
      it finds a place to stand
  - an attacker creep can only ever target a TOWER. The builder and technology
    discs cannot be attacked at all - not "are tough", not "are ignored while a
    tower is in range": they are not valid targets, ever. Enforced by their
    being invulnerable rather than by a list of exceptions. See unit_data.md
    - so a disc is a square of a maze that an attacker can do NOTHING with -
      it cannot destroy one and it cannot be blocked by one either, since a
      disc is not a wall in the first place. That is the whole trade: a disc
      is a square that never opens and never closes
  - what it destroys leaves rubble, see Towers and attacking
  - **being an ATTACKER is asked before anything about how it travels.** One of
    them flies, and a flyer reads none of the maze and goes straight down the
    lane - so asked the other way round it sailed straight past the maze it had
    been sent to take apart. What an attacker is is what it goes after; how it
    gets there is a separate question
  - one of them is also the only creep in the game with an ACTIVE ability, and
    the only thing its owner AIMS. It dives out along the aimed direction and
    back, burning what it passes over, and Stop calls the dive off - which pays
    it back the armour a maze has eaten off it, so cancelling is a decision
    rather than a mistake being undone
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
- **SUDDEN DEATH is that exception, and it is the only time a creep is ever
  taken AWAY from a player.** BUILT.
  - at a fixed point on the match clock the whole of Tier 4 unlocks at once -
    no per-creep start delay, unlike every other tier - and Tiers 1 to 3 stop
    being sendable for the rest of the match
  - each sender answers it for itself rather than a rule reading a tier
    NUMBER: one of them is the Sudden Death sender and is shut until it
    arrives, and every other one is open until it arrives and shut afterwards
  - anybody below an income FLOOR is raised to it, once, at that moment. A
    player who has been losing slowly for the whole match would otherwise reach
    the one tier that can end it and be unable to afford any of it
  - Tier 4 creeps stop paying properly above an income CAP: over it, a Tier 4
    send grants a fraction of its stated income. Only Tier 4, and only above
    the cap - the point is to stop Sudden Death compounding, since by then the
    creeps are meant to be ending the match rather than paying for the next one
  - one creep is refused outright above that cap rather than merely paying
    less, because it is nothing BUT income and a cheaper version of it would be
    a creep with no purpose left
  - the clock, the floor, the cap and the share are all in
    `game_config.tres`; the creeps are `unit_data.md` 6.5
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

**THE WHOLE ROSTER IS IMPLEMENTED** - all four tiers, plus the Timber Wolf that
only ever arrives inside a Sheep pack and the Ghoul that only ever crawls out of
a dead Obsidian Statue. The numbers are `unit_data.md` 6.2 to 6.5's, which are
the source game's; the creeps' `.tres` files are the authority and those
sections are the mirror.

The Ancient Wendigo was built out of order, well before the rest of tier 3, for
a reason that was about testing rather than about design: every tier 1 creep
dies to a single shot from any tower above the cheapest tiers, so there was
nothing on the field a real tower could be measured against. It brought the
first creep trait whose armour is not a constant - Hardened Skin, which wears
off as the creep is hit - and the first sender above Tier 1.

Tier 2 brought three things the roster had never needed:

- **mana on a creep**, for the trait that banks a point per hit taken and
  spends the lot on a heal. See the Mana section
- **a creep that shoots**, for the one that lobs at a random tower nearby on a
  clock of its own rather than walking up to anything. It is a second attack
  running alongside the creep's own
- **the other two halves of a spell resistance**, which were written down long
  before anything in the game applied a slow or a timed debuff. The elemental
  towers made them real. See Status effects

Tiers 3 and 4 brought the rest, and most of it is machinery the roster had
never needed:

- **damage absorption shields**, for the creep that converts nine tenths of
  itself into one. A shield is a POOL rather than a resistance and is spent
  last of all, after every ratio and every block - see Status effects
- **creeps that spawn other creeps**, for the one that leaves three behind
  where it dies
- **effects a creep leaves on a TOWER**, which is the first traffic in that
  direction: a curse on a tower's attack speed, an aura weakening its damage,
  and a creep that drains a tower's mana and keeps far more than it took
- **a creep that walks THROUGH the maze** rather than around it, and one that
  DODGES attacks from the long ranged half of it
- **an ACTIVE ability on a creep** - the roster's only one. The Phoenix is
  aimed by its owner, dives out along that line and back, and can be called off
  with Stop
- **Sudden Death**, which is the one place a tier means anything at all

A SEND is a pack rather than a count: nearly every one is three of the same
creep, a Boss is one, and the Sheep is two Sheep and one Timber Wolf. What a
send spawns is the creep's own answer, so a pack that ever grows a second escort
is another entry in its file rather than a rule anywhere.

# Sending creeps
- Creeps are bought from a SENDER, and a sender has no body. BUILT.
  - it stands nowhere on the map: no model, no footprint, no strip of ground
    above the spawn zone, nothing to click, nothing on the minimap, and no
    marker for the camera to fly to
  - it is still an ordinary unit in every other way, and has to be: an order
    names a unit over the wire and the server checks that the card really
    carries the ability, so a sender is a registered unit with a card
  - it is invulnerable and permanent, which follows from its armour type rather
    than from a rule of its own
  - **one sender per creep TIER**, as in the source game, because a tier is
    exactly twelve creeps and twelve is exactly one command card. Each knows
    which tier it is, so a tier with nothing implemented yet has no sender at
    all and the others notice nothing
  - a reserve belongs to the CREEP TYPE rather than to a sender or a square, so
    re-laying the card out can never move somebody's stock, and the cheat that
    opens the card opens every sender at once
- A sender is reached through a ROW OF SQUARES over the unit panel, one per
  tier, left to right. BUILT.
  - pressing one selects that sender, which puts its creeps on the unit panel
    like any other selection. That is the whole of what a square does - nothing
    is sent from the row itself
  - the row is always as long as there are tiers, whatever is built. A tier
    with no sender is drawn DEAD rather than left out, so the square a player
    has learned to reach for never moves when a tier is filled in
  - a sender can be put in a CONTROL GROUP like anything else, which is how it
    is reached by keyboard now that there is nothing to click in the world
  - two senders can never share a selection, and neither can a sender and
    anything else. Each draws a different card, so a selection holding two
    would have to pick one and quietly drop the other
  - recalling a sender's control group twice does not centre the camera. There
    is nowhere to centre it
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
  - a locked creep's square is covered whole, counts the seconds left down
    across its middle, and reads a reserve of zero. Its tooltip says when it
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
  - A reserve holds NOTHING until its creep unlocks, and is handed its starting
    stock at that moment. `unit_data.md` is the authority on what that is, and
    on which creeps get a smaller one of their own
    - dormant rather than merely empty: a reserve that replenished through the
      start delay would be full the second its creep opened, which is the
      opposite of what the delay is for
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

# The player's name
BUILT.

- A player is asked what to call themselves the FIRST time they open
  multiplayer, and cannot go online until they have chosen. The prompt is
  modal: everything behind it is dimmed and nothing behind it can be pressed
  - it is asked BEFORE the connection is opened rather than after, because a
    client states its name once on arriving and never again
  - there is no way past it on a first run - no Cancel, and Escape does
    nothing. A player who is CHANGING a name they already have can back out,
    because nothing is waiting on them
  - the box opens with the machine's own login name as a SUGGESTION, and
    silently offers nothing at all when that would break a rule. It is not an
    answer: a machine login is not a thing anybody picked to be known by
- It is CHANGED from a button in the multiplayer panel showing the current
  name, which opens the same prompt with a way out on it
- **The name is a thing to display, never a claim to trust.** The server
  sanitises whatever a client states about itself and the peer id remains the
  identity, so the rules below are about what makes a legible name rather than
  about who somebody is
- What a name may be: LETTERS and DIGITS, plus space, underscore and hyphen
  inside it, starting with a letter or a digit, between a floor and a ceiling
  on its length. Deliberately unicode, so a name that needs an umlaut does not
  have to be spelled wrong
  - what it refuses is PUNCTUATION and SYMBOLS - what people use to impersonate
    somebody else, to draw shapes in a lobby list, or to pad a name out with
    things nobody can say out loud
  - the prompt says WHY a name is refused rather than only grey out its button,
    and it is the same call the store gates on, so the two cannot disagree
- NOT BUILT: a profanity filter. Nothing checks what a name says, only what it
  is made of
- It is kept on the machine that typed it, with the video and audio settings
  rather than in a `.tres` - it is written at runtime by whoever is sitting
  there. See the note on UserSettings in the README

# Player colours
BUILT.

- Every player has a COLOUR, and it is per-match identity: it is what anything
  showing several players at once tells them apart by, and the only thing
  naming a player at all in an ANONYMOUS match
- It is CHOSEN IN THE LOBBY, from a dropdown on that player's own row. Only
  your own row carries one - a colour is yours and nobody else's - and every
  row shows the colour itself beside the name so the roster reads at a glance
- **A colour is not a slot, and choosing one moves nothing.** A slot is a LANE,
  dealt out by the server and re-dealt when somebody leaves or when the lanes
  are shuffled; a colour is chosen and then kept. So picking one never changes
  where a player sits in the lobby, and being moved never changes their colour
- **Unique within a lobby.** The server assigns and validates, so a colour
  somebody else holds is refused rather than duplicated - two of a colour could
  not be told apart on a minimap, and in an anonymous match they would be two
  players with the same name
  - a colour another player holds is drawn GREYED in the dropdown rather than
    left out of it, so a player can see what all of them are and which are gone
  - the request takes the same round trip every other order does, and the row
    is redrawn from what the server sends back. Two players reaching for the
    same colour in the same second is exactly what that is for
- **Nobody sits colourless.** Joining hands out the first free colour in the
  palette, so the first player in is red, the second blue, and a match can be
  started without anybody opening the dropdown
  - somebody leaving frees theirs and leaves a GAP rather than shuffling the
    colours below them along. The next joiner takes the gap
- The palette and the names are in the presentation config, in the source
  game's own order, which is what makes the default deal an RTS palette rather
  than an arbitrary one. Reordering it re-colours every default
- NOT BUILT: teams. Free for all only, so a colour says WHO and never WHICH SIDE

# Match settings
BUILT.

The HOST chooses what kind of match this is, IN THE LOBBY, before anybody loads.
The source game asks these questions once everybody is already in the world
because Warcraft III gave it nowhere else to ask them; this build has a lobby,
so the answer is known before a single area is placed.

- Everybody in the lobby SEES the settings; only the host may CHANGE them
  - the server refuses a change from anybody else, so the greyed-out panel a
    joiner is looking at is a courtesy rather than the rule
  - and it refuses one from the host too once the start countdown is running:
    the roster and the rules become final at the same moment
- The DEFAULTS live in `game_config.tres`, and the lobby takes a copy of them
  - so editing that file still changes what every new match starts from, and a
    match that was started carries what was actually agreed rather than what
    the file happened to say later
- RANKED is a match played on those defaults and nothing else. Every other
  setting is forced back to its default and locked, so two ranked results are
  comparable
  - the ONE exception is the technology mode, which the host still chooses. It
    changes what the match is about rather than how generous it is, and all
    three answers cost the same free technologies

What can be set, in three groups:

- RESOURCES: lives per player, starting gold, starting free research points,
  starting income, and the income interval
  - lives follow the PLAYER COUNT on their own - the pool split between however
    many are in the lobby, see Life steal - and the reading moves as people come
    and go. A host who types a number over it keeps that number whoever turns up
- CREEPS: the whole roster, or without flyers, or without attackers, or without
  either
  - a creep the match left out is not on anybody's send card AT ALL, which is
    also what makes the server refuse an order for one: an ability that is not
    on a unit's card is refused for every unit in the game the same way
  - the square it would have sat in is left empty rather than closed up, so the
    rest of the card stays where a player learned it
- RANDOM LANES: the roster is dealt into the lanes at random when the match
  starts, so who sends into whom is not the order people happened to join in
- TECHNOLOGY MODE: how the free opening technologies are handed out
  - PICK: the player spends them in the Research Center themselves, whenever
    they like. The game as it is without this setting
  - RANDOM: one Ultimate is rolled for the whole match and handed to everybody,
    so every player opens on the same tower
  - DRAFT: three Ultimates are rolled for the whole match, every player is
    offered the SAME three, and each takes one
    - **the world is held still until they all have.** Nothing moves, nothing is
      spent, no clock runs and no creep unlocks - and the match clock is given
      back exactly what the wait took, so the draft costs nobody a start delay
    - a player who leaves during it stops being waited for, so one crashed
      client cannot hold everybody else for the rest of the match
  - whichever way it is dealt, the opening is what the match gave you: it cannot
    be handed back through the undo window the way a bought technology can
- MODIFIER: Anonymous shows players by their COLOUR instead of by name, in the
  match only. The lobby still shows real names - the anonymity is a rule of the
  match, and hiding who you are about to play would only stop people finding
  each other

Nothing here is per player: it is what the whole match agreed to, and it is
fixed for the life of that match.

# Economy
- Gold is spent on towers and on sending creeps
- Income is paid out on a fixed interval
  - One shared clock, so every player is paid on the same beat
- Starting gold, starting income and the payout interval are MATCH SETTINGS: the
  host chooses them in the lobby and `Resources/Config/game_config.tres` holds
  the defaults they start from. See Match settings
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
  - That is what a lobby shows until somebody changes it, and the reading moves
    as players come and go. A host may type a number over it in a custom game,
    and then it stays put whoever turns up. See Match settings
  - The SOURCE GAME instead sets them per player count and per ruleset, and those
    figures are in `unit_data.md` section 1.7. Adopting them is pending a ruleset
    concept, which does not exist yet
- Bosses steal more than one life. How many is per creep, in the roster
- **THE LEAK LOG.** BUILT. Every life that changes hands is announced on screen,
  above the command card: newest at the bottom, older ones pushed up, gone after
  a few seconds
  - a player is only ever shown the leaks they are AT ONE END OF. A life is
    stolen rather than lost, so a leak has two ends and only those two are worth
    telling either player about; a twelve player match generates one somewhere
    almost every second. The server announces all of them and the HUD filters,
    so a spectator - when there is one - can be shown the whole ledger without
    the server learning about it
  - the other player is named in THEIR OWN COLOUR, by whatever the match calls
    them, so an anonymous match names them by colour without the log knowing the
    rule. See The player's name
  - two leaks the same way round in a row are ONE line with a bigger number
    rather than the same sentence twice, and the second one restarts its clock
  - the stack has a CEILING. A line pushed past it by newer ones is gone at once
    rather than fading, so a bad wave cannot walk the log up the screen
  - what is deliberately NOT in it, unlike the source game, is which creep leaked
    and at what health
- **CATCH-UP GOLD.** BUILT. When a player is eliminated, whoever they were
  attacking is handed a one time lump of gold for the attacker they have just
  been given instead
  - losing an attacker is not a reprieve. The ring closes and the next player
    round it takes over, and that player has been fighting somebody else all
    match and may be several tiers of income ahead
  - the lump is a multiple of what the NEW attacker earns per income tick, so
    it scales with how big a step up they are rather than being a flat number
    that means nothing by the twentieth minute. The multiple is in
    `game_config.tres`
  - paid to the DEFENDER, never to the new attacker, and once per hand-over
  - it never fires in a 1v1: there is nobody for the ring to hand over to, and
    a match whose second player is gone is already over
  - the SOURCE GAME pays this differently - on a new attacker whose income is
    HIGHER than the last one's, and at 1.5x the difference. `unit_data.md` 1.7
    records both and says which is which

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
- The DISCS are in the same position as the towers: their structure, prices and
  effect numbers are the source game's, and two things about them are not
  - the visual language above - round on square, the circle's colour saying the
    element and its size saying the tier. Nothing in the source looks like this
  - the Ultimate tier's own effect numbers, which the 9.4 disc sheet does not
    record at all - only its base and Advanced tiers. `unit_data.md` 5.2 marks
    them as supplied for this project rather than copied
- The senders' display names are still placeholders, all four of them
- Creep models are primitives varying only by shape, size and colour. Tower
  models are primitives too, but to a deliberate system - see Presentation
- Creep separation strength is a tuning value you change while testing. Whatever
  it currently reads is a test state, not a decision - and the waypoint bug it was
  once masking is gone, so it is worth a real call at some point
- So is the share of its selection circle an ATTACKER keeps clear, and how near
  an ordered point a crowd counts as arriving. Both were set to feel their way
  to a number rather than decided, and both are one value in the match config

# Open questions
- Recycling rule generalisation for 3+ players (deferred)
- Map layout for more than 2 players (deferred)
- Whether to adopt the source game's per-ruleset starting lives, which needs a
  ruleset concept first. See Life steal
- Whether Sudden Death should also make creeps progressively tankier. The
  source game lowers the damage they take by a share every minute for the rest
  of the match; `unit_data.md` 1.7 has the figure and marks it NOT BUILT. It is
  the only Sudden Death rule of the source's that was not copied
- Whether a technology tower should refund less than a Basic one when sold. The
  source game splits them; here one share is shared by every building. Listed
  under the elemental abilities above, because that is where it bites

Answered since, and kept here only so the answers are not re-asked:

- CATCH-UP GOLD is built, on a rule of the user's rather than the source
  game's: it fires when a player is eliminated and pays the defender a
  multiple of their NEW attacker's income. See Life steal and recycling
- The send tooltip DOES state what a pack holds, and spells the contents out
  wherever a pack holds more than one kind
- The source game's FOUR send buildings were copied, one per creep tier, and
  the row of squares over the unit panel is how they are reached. See Sending
  creeps
