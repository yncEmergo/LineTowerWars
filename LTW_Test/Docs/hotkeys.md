# Hotkeys

How a key reaches a command: the grid every card is laid out on, where each kind of ability
sits on it, which commands can be given a key of their own, the Research Center's second grid,
the keys that never change, and which of two things wanting the same key gets it.

**This is the one `.md` allowed to name keys and squares.** Everywhere else the rule in
`CLAUDE.md` holds. The exception is deliberate: the grid is a set of physical keys under the
left hand rather than a value anybody tunes, so writing it down costs nothing and saves every
reader from rebuilding it out of `.tres` files. A layout that does change is changed HERE and in
its generator or `.tres` in the same commit, and the boot check refuses content that breaks
section 2, so the two cannot drift apart silently.

**Status: written 2026-09-25 as the spec for the hotkey rework, and built the same day.**
Everything below is the rule and is what the code does. Section 9 lists what is still open; it
is deleted when it is empty. `game_rules.md` points here for everything about keys.

Related: `game_rules.md` for everything about the controls that is not a key, `Docs/ui.md` for
what is drawn in front of what, `Scripts/UI/FocusPolicy.gd` for why no key ever moves keyboard
focus.

---

## 1. The grid

The command card is 4 x 3 squares, and every square is a KEY POSITION: the physical key at that
place on the keyboard, whatever is printed on it. Written here as a German board prints them:

```
Q W E R
A S D F
Y X C V
```

- **The position is the key, never the letter.** On an American board the bottom left key
  prints Z; on a French one the top row prints A Z E R. The square still answers to the key in
  that place, and draws whatever the player's own keyboard prints there, which is asked of the
  OS. No setting says which layout a player has, because nothing needs to know
  - that is what a grid is: a shape the hand learns once. Stored as letters it needed a layout
    setting, and was wrong on every layout nobody had set it up for
- **The square decides the key, never the other way round.** Every ability names exactly one
  square. There is no automatic placement, no square claimed ahead of another, and no pushing an
  ability along to make room
  - a card with an ability on no square, or two abilities on one, refuses to boot
- **A grid key only ever means a square.** Nothing else in the game answers to one, no command
  can be bound to one, and nothing yields to the card to borrow one
- **An empty square's key does nothing**, and neither does a passive's: a passive owns its
  square but has nothing to press
- **On the command card, Shift does not change which square a key presses.** It only decides
  whether the order waits behind the one already running. See `game_rules.md`, Controls. (The
  Research Center is different: its bottom rows ARE the Shift layer, section 4)
- A square draws its key in its top left corner, and its tooltip names it

## 2. What goes where

**These layouts are binding.** A card that breaks one refuses to boot. They are the reason a
player learns the game's keys once rather than once per unit.

### 2.1 Towers

```
Q Upgrade 1    W Upgrade 2    E Prioritize Air    R Ability
A Attack       S Sell         D Passive 2         F Passive 1
Y Return       X  -           C  (Cancel)         V Show Ranges
```

- **Q and W are the upgrades**, in path order. A tower with one upgrade takes Q alone, so the key
  that moves a tower up its line is the same key at every tier, and choosing a path is the same
  two keys on every tower that branches
- **R is the tower's own ability that is PRESSED**: Alter Armor on the Ultimate Alchemist,
  Stampede Target on every Beastmaster tier. It is empty on every tower without one, and nothing
  else ever sits on it
- **Passives take F, then D.** A tower's named ability is on F, so where to read what a tower
  does never moves. A second passive goes on D (the Ultimate Harbinger's Void Conversion). S
  would be next, but on a tower S is Sell
- **E is Prioritize Air**, on the towers that can choose
- **A is Attack and S is Sell**, on every tower
- **Y is the way back down**: Return to Elemental Core, on the towers that carry it
- **V is Show Ranges**, on every tower
- **C stays empty**, because Cancel appears there while the tower is being built, sold,
  upgraded or returned (2.6)

### 2.2 Technology discs

An active disc is laid out as a tower with nothing to shoot:

```
Q Upgrade      W  -           E  -                R  -
A  -           S Sell         D  -                F Passive
Y Deactivate   X  -           C  (Cancel)         V Show Ranges
```

- **Y, Deactivate Disc, is the way back down**, on the same square as Return to Elemental Core

### 2.3 Creeps

```
Q Move         W Stop         E  -                R Ability
A Attack       S Passive 3    D Passive 2         F Passive 1
Y Flying       X Boss         C Attacker          V  -
```

- **Move, Stop and Attack** exist only on a creep that takes orders
- **R is the creep's own ability that is pressed** (Dive, on the Phoenix) and is empty otherwise.
  It is the same square as a tower's, so "this unit's ability" is one key in the whole game
- **Passives take F, then D, then S**, in the same order a tower's do
  - a passive several creeps share is ONE resource with one square, so it sits on the same
    square on every one of them. A creep's own passives take what is left of F, D and S, in card
    order
- **Traits take the bottom row, one square each**: Flying Y, Boss X, Attacker C. Power of the
  Destroyer is the Obsidian Statue's version of Boss and shares X, since no creep has both
  - a trait is a fact the creep's stats own, drawn on the card so it can be read. A square of its
    own means "this one flies" is found in the same place on every flyer

### 2.4 The builder

```
Q Move         W Stop         E  -                R  -
A Attack       S  -           D  -                F Build
Y Blueprints   X Build Grid   C  -                V Save Blueprint
```

- Move, Stop and Attack are on the same squares as a creep's
- Build opens the build menu. Blueprints and Save Blueprint open the two blueprint lists (2.5)
- It is laid out as it is rather than to a pattern: there is one builder, with no passive and
  no ability of its own to be consistent with

### 2.5 Choosing cards

A card where every square is one choice of the same kind. Each keeps its own layout.

**Elemental Core and inactive Technology Disc.** One layout for both, generated from one table,
so the key for an element is the same on either:

```
Q Ice          W Lightning    E Holy              R Unholy
A Fire         S Sell         D Earth             F Arcane
Y Water        X Void         C Primal            V Show Ranges (the Core only)
```

- Sell is on S here, as on every other card. Water gave the square up for it: continuity with the
  rest of the game won over the source game's layout
- Show Ranges is on V as on every tower, so it is on V on everything that shoots. The inactive
  disc leaves V empty: it has nothing to show
- The Core carries no Attack or Prioritize Air, for want of room. It still attacks

**The build menu**, from the builder's Build:

```
Q Lesser Archer    W Lesser Cutter     E Lesser Sentry     R  -
A Elemental Core   S Technology Disc   D  -                F  -
Y  -               X  -                C  (Cancel)         V  -
```

- the Basic lines across the top in line order, and the two special buildings below them

**The blueprint lists**, from Blueprints and Save Blueprint: Blueprint 1 to 9 in reading order
from Q to Y, so a slot answers to the same square on both lists. The save list adds Restore
Default Blueprints on V. C is Cancel.

**The send buildings.** Every square is one creep of that tier, in the order the tier's `.tres`
lists them. A creep the match was set up without leaves its square EMPTY rather than closing the
gap, so the rest of the card stays where it was learned.

### 2.6 Cards that stand in for another

- **While an order is being aimed**, the card is empty except Cancel on C. A right click cancels
  it too
- **A submenu** (the build menu, the blueprint lists) replaces the card, and Cancel on C backs
  out of it. C is left free on every submenu for that
- **A building on a clock** (being built, sold, upgraded, or returned to a Core or an inactive
  disc) shows only its Cancel, on C
- So **C means Cancel wherever Cancel can appear**

### 2.7 Several units, and other players' units

- **Several selected units** draw the abilities all of them share. Those are the same resources,
  so they are on the same squares. A subgroup (Next Subgroup, section 3) draws that kind's own
  card
- **An opponent's unit** draws its passives and traits on their squares, and nothing else.
  Reading the creep walking at you is part of the game; an order the server would refuse is not

## 3. Commands with a key of their own

A short list of commands can be given a key of the player's choosing, on the Hotkeys page of
the options screen. It is short on purpose and stays short: there are hundreds of abilities and
twelve squares, which is the whole reason the grid exists. A command earns a place by meaning
the same thing on every card, or by not being on a card at all.

| Command | Out of the box | Notes |
| --- | --- | --- |
| Sell | its square, S | every Sell on every card |
| Build | its square, F | the builder's build menu |
| Cancel | its square, C | every Cancel: a build, a sale, an upgrade, a return, an aimed order, a submenu |
| Research Center | G | opens it. G does NOT close it, see section 4 |
| Next Subgroup | Tab | Shift+Tab steps back |
| Select Builder | B | pressed twice, it also centres the camera on the builder |

- **A command on the card keeps its square.** Binding Sell to T moves Sell's KEY and never Sell
  itself: the square draws T, and S does nothing on any card Sell is on
- **A grid key can never be bound**, and neither can a fixed key (section 5). Anything else can,
  the Research Center's letters included
  - the one grid key a row accepts is its OWN square's: pressing S on Sell's row puts Sell back
    on S
- **One key, one command.** Binding a key another command holds takes it, and leaves that
  command UNBOUND
- **Unbound means no key at all.** A command on the card does NOT fall back to its square: a
  player who moved Sell off S to stop selling by accident must not quietly get S back. Its
  square draws no key, and a Select Builder or Research Center without one draws none on its
  action bar square
  - **the Hotkeys page shows a red "[command] is unbound!" line for every command without a
    key**, for as long as it stays that way
- **Backspace or Delete** on a row unbinds that command. **Reset All** puts every command back to
  what it had out of the box
- A binding is saved in `settings.cfg` under the command's `action_id`, as a key POSITION. A
  command the player never touched follows its default if the default ever changes
- The mouse can never be bound. Its side buttons carry control groups (section 5)

## 4. The Research Center

The second grid, for the one screen that is not about the selection. Six keys wide, because a
row holds two elements of three technologies each: the card's three rows extended two keys to
the right, then the top two rows again with Shift.

```
          no modifier                                  with Shift
Q W E | R T Z    Fire      | Unholy        Q W E | R T Z    Holy | Arcane
A S D | F G H    Ice       | Water         A S D | F G H    Void | Primal
Y X C | V B N    Lightning | Earth
```

Each element's three are its Basic technology, then (1), then (2), from left to right. Which
technology sits on which square is authored on the technology itself, in `Resources/Tech`.

- **It counts as the SELECTION.** Opening it clears whatever was selected, which cancels an order
  being aimed (orders already queued keep running). Selecting anything closes it: a unit, a box,
  a control group, a send square, the builder square, and a click on empty ground, since that
  is how a selection is cleared
- **While it is open, it owns every key its grid covers**, including keys that mean something
  everywhere else: B researches Earth (1) instead of selecting the builder, and G researches
  Water (1) instead of closing the screen. Keys outside its grid keep their meaning
  - so it can never collide with the card, which is empty while it is open, and a command bound
    to one of its keys is simply out of reach until it closes
  - a slip is what its Undo button is for
- **Opened** by G, or by its square on the action bar. **Closed** by Escape, by the close button
  (✕) in its top right corner, by its action bar square, or by selecting something
  - the close button is a glyph rather than the letter X, which would read as the X key in a
    screen where every square draws its key
- **Closing it without selecting anything puts back what was selected when it opened**, minus
  anything that has died since, so a look at research does not cost the player their builder

## 5. Keys that never change

Answered wherever the player is, never offered for binding, and refused by the Hotkeys page with a
line saying why. **One table in `ControlsConfig` lists them**, and both the Hotkeys page and the
boot check read it, so no key can be answered somewhere and forgotten here.

| Key | Does | Answered by |
| --- | --- | --- |
| the grid keys | the command card, section 1 | `UnitPanel` |
| Escape | backs out of one thing, section 6 | whatever is on top |
| F10 | opens and closes the game menu | `GameMenu` |
| 1 to 9 | control groups: recall, twice to centre the camera, with Ctrl to assign. The send buildings start on 1 to 4, tier by tier, unless an option says not to | `SelectionController` |
| Mouse 4 and 5 | two more control groups, unless the setting hands them back | `SelectionController` |
| Arrow keys | pan the camera | `RTSCamera` |
| Shift, Ctrl, Alt, Meta, CapsLock | nothing on their own. Shift queues an order and adds to a selection | - |
| Backspace, Delete | unbind, on the Hotkeys page | `HotkeyRow` |
| Numpad digits | developer keys: cheats and tutorial skips, where cheats are allowed | `CheatController`, `TutorialDirector` |

- **Ctrl with a number does nothing while nothing is selected.** It would otherwise empty that
  group, and with the Research Center clearing the selection that is only a press away

## 6. What a key press reaches first

1. **A text field being typed into** takes its keys
2. **Something waiting for an answer.** The Hotkeys page listening for a key takes the next
   press, whatever it is (Escape stops it listening, Backspace and Delete unbind). A confirm
   prompt takes Enter and Escape and lets nothing else through
3. **F10 and Escape.** Escape backs out of one thing per press, whatever is on top: the game
   menu (the options screen first when it is open), the Research Center, an order being aimed,
   a submenu. With nothing left to back out of, it opens the game menu
4. **The Research Center's grid**, while it is open: every key it covers
5. **Keys that mean the same everywhere**: the control groups, Select Builder, the Research
   Center's key (to open it), Next Subgroup, the camera
6. **The command card**: a grid key presses its square, and a card command's own key presses
   that command

Two pairs in this list can never compete, which is what keeps it honest: 4 and 6, because the card
is empty while the Research Center is open, and 5 and 6, because a grid key can never be bound.

## 7. Holding a key

- Holding a key repeats its ability, starting slowly and ramping up to a capped rate. The
  timings are in `controls_config.tres`
- **Opt-in per ability**, and the sends are what opt in: leaning on a key must never repeat Sell
  or Cancel
- The repeat stops the moment the key comes up, the card changes, or the Research Center opens

## 8. Where it lives

- `Scripts/Config/ControlsConfig.gd` and `Resources/Config/controls_config.tres`: both grids'
  shapes and key positions, the passive and trait squares, the fixed keys, the hold timings
- `Scripts/Input/KeyPosition.gd`: a key as a position - read off a press, stored, and drawn as
  whatever the player's own keyboard prints there
- `Scripts/Abilities/CardLayout.gd`: the boot check that holds every card to section 2. It runs
  from the content walk `Main` starts, once per card
- `Scripts/Config/HotkeyAction.gd` and `Resources/Config/Hotkeys/`: the commands with a key of
  their own. A new one is a `.tres` added to `hotkey_actions`
- `Scripts/Config/UserSettings.gd`: what the player bound, in `settings.cfg`
- `Scripts/UI/UnitPanel.gd` lays a card out and answers its keys; `Scripts/UI/CommandSlot.gd`
  draws one square
- `Scripts/UI/ResearchCenter.gd`; `Scripts/UI/ActionBar.gd` for the builder and Research Center
  squares; `Scripts/Input/SelectionController.gd` for control groups and subgroups
- `Scripts/UI/Menus/OptionsMenu.gd` and `Scripts/UI/HotkeyRow.gd`: the Hotkeys page
- **The squares themselves.** Generated, so change the generator and re-run, never the `.tres`:
  - `Tools/ModelGen/element_content.py`: elemental towers, the Core's layout (shared with the
    inactive disc), Return to Elemental Core, the tower abilities on R, the Core's build square
  - `Tools/ModelGen/disc_content.py`: the discs and the disc's build square
  - `Tools/ModelGen/tower_content.py`: the Basic towers, the build menu's top row and the
    builder's Build square
- Authored by hand, each in its own `.tres`: the builder's card, creep passives and traits, the
  shared abilities (Move, Stop, Attack, Sell, the Cancels, Prioritize Air, Show Ranges), the
  blueprint lists and the send cards. A technology's square is on its own `.tres` in
  `Resources/Tech`

**Testing it.** A key a tool injects often carries no physical code, and is then read as the
position its keycode NAMES - the US QWERTY key of that name. So the bottom left square is
pressed by sending Z, on any machine. And a headless process cannot ask what a key prints, so
there every square draws its position's US name instead: check labels in a windowed run.

## 9. Still open

- [ ] The tutorial's research lessons assume the selection survives opening the Research
  Center, and it no longer does. Re-check them with `TutorialProbe`
