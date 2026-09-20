# UI

How this game's interface is built, and the rules a change to it has to keep.

**This file is meant to grow.** Today it carries two subjects - what is drawn in
front of what, and how a Control is animated - because those are the two that
have already been got wrong. The patterns that are not written down yet (how a
panel is laid out, how a prefab carries its own behaviour, how a screen is
opened and closed) belong here too, each as its own numbered section, added when
somebody has something durable to say about it. Keyboard focus is the exception and is already written down: it
lives in `Scripts/UI/FocusPolicy.gd`, next to the one call it needs.

Related: `CLAUDE.md` for the engine traps and the naming conventions,
`Scripts/UI/FocusPolicy.gd` for focus, `Docs/audio.md` for how a button gets its
click.

---

## 1. Ordering

What is in front of what. **Every ruling in this section is binding**, unlike the
visual language in `game_rules.md`, because getting one wrong produces a panel
that covers a menu nobody can then read or press.

### 1.1 What the engine actually does

Four rules, in the order the engine applies them:

1. **A higher `CanvasLayer.layer` beats everything below it.** Layers do not
   interleave: every canvas item on layer 1 is in front of every canvas item on
   layer 0, whatever the tree says.
2. **Inside one layer, a child draws in front of its parent.**
3. **Inside one layer, siblings draw in TREE ORDER - the LATER child is in
   front.** This is the one that decides almost everything in this project.
4. `z_index` re-sorts siblings ahead of rule 3, and is banned here. See 1.3.

And one more, which is not a drawing rule at all and is the reason 1.3 exists:

5. **The mouse picks the Control under it in REVERSE TREE ORDER, and never looks
   at `z_index`.** So tree order is the only thing that moves drawing and
   clicking together.

### 1.2 The mechanism is TREE ORDER, and nothing else

**A node is put in front of another by being LATER IN THE TREE. That is the
project's only layering mechanism, and a change that needs a different answer
moves the node.**

It is the only one because it is the only one that keeps drawing and clicking in
agreement. Everything else - `z_index`, a second `CanvasLayer`, `top_level` -
moves one of the two and leaves the other where it was, which produces a panel
that is visibly on top and still loses its clicks to something underneath, or a
panel that eats clicks while being invisible. Both read as a dead button rather
than as a layering mistake, which is what makes them expensive.

So:

- **Never call `move_to_front()` or `move_child()` to raise a panel.** The order
  is authored in the `.tscn` and read there. A container reordering its own
  list items is not layering and is fine.
- **Never add a second `CanvasLayer` to get something on top.** Besides splitting
  the ordering into two mechanisms, a `CanvasLayer` between two Controls breaks
  the `focus_behavior_recursive` chain - see `Scripts/UI/FocusPolicy.gd`, which
  already pays for the one the HUD has.
- `top_level` detaches a node from its parent's transform. It does not change
  what draws in front, so it is never the answer to an ordering question.

### 1.3 `z_index` is BANNED for UI layering

**Measured on 4.7.2**, with two overlapping Buttons in one parent, the EARLIER
one given `z_index = 10`:

| | result |
| --- | --- |
| drew on top | the early one - `z_index` won |
| took the hover | the late one |
| took the click | the late one |

So a `z_index` raised to put a screen in front buys the pixels and not the
input. The screen looks modal, and every click on it lands on whatever happens
to sit later in the tree.

`DesyncNotice` was written that way. It got away with it only because it
separately swallows every key and every mouse button in `_input`, so nothing
underneath could act on the clicks it was losing - which is to say the bug was
there and was masked. It is now simply last in the HUD's tree, and sets no
`z_index` at all.

The ban is on LAYERING. `z_index` on a node with no interactive siblings to lose
a click to - inside one self-contained widget, say - is not what this is about,
but there is no case in this project that needs it.

### 1.4 The HUD's bands

`Scenes/UI/match_hud.tscn` is ONE `CanvasLayer`, and its direct children are
authored bottom-to-top in these bands. **The scene is the authority on which node
sits in which band; this list is the authority on which band comes first.**

| # | Band | What belongs in it |
| --- | --- | --- |
| 1 | **World overlay** | Drawn over the 3D world and UNDER every panel. It marks or dims things in the WORLD - a selection box, a spotlight on a lane. If dimming the HUD as well would be wrong, it is band 1. |
| 2 | **HUD** | The panels that are always on screen and are read at a glance while playing: the bars, the stats, the minimap, the command card, the leak log. Nothing in this band covers anything else in it. |
| 3 | **HUD screen** | A large panel that is part of PLAY and deliberately covers the band above, but takes neither the whole screen nor all the input - the research screen. |
| 4 | **Tutorial** | Guidance drawn over the HUD it is pointing AT: the lesson board, the pointer's border and its dim, an explanation page. It must cover band 2 and 3, and must be covered by band 5 - a lesson that outranks the game menu is this document's founding bug. |
| 5 | **Modal** | Takes the screen and the input: the game menu and its options screen, a draft, a countdown, a confirmation, the end-of-match panel. |
| 6 | **System** | The match has stopped being playable and says so: a stall, a desync. Outranks every modal, because a modal raised over one of these would offer choices that no longer mean anything. |

A node that draws nothing - a plain `Node` holding a script - is outside the
bands and goes at the very end, where it cannot be mistaken for a layer.

### 1.5 Where a new HUD node goes

**In its band. NOT at the end of the file**, which is where the editor puts it
and where the founding bug came from - a tutorial board appended after the game
menu, which is how a lesson ended up drawn over the options screen along with
the gold border the pointer frames a button with.

Pick the band with the two questions in order:

1. **What must it cover?** That sets the floor.
2. **What must cover IT?** That sets the ceiling.

If the honest answer is "it must cover a modal but not a stall", it is band 5,
last. If both answers name the same band, it belongs in that band and the rule in
1.6 decides where.

If nothing in the table fits, say so and add a band rather than wedging the node
into a neighbouring one - a band is cheap and a node in the wrong one is a bug
that surfaces months later, in the one state where two panels are up at once.

### 1.6 Inside a band

**The one that can be raised ON TOP OF another goes later.** Most band members
never coexist, and for those the order does not matter and should not be argued
about. Where two genuinely can be up together, ask which one the player summoned
second, and put that one after.

This is why the game menu is last in band 5: it answers a key that can be pressed
over anything, and the escape that closes it closes exactly one layer at a time.

### 1.7 Screens outside the HUD

A menu screen - the main menu, the lobby browser - is a plain `Control` with no
`CanvasLayer`, so rules 2 and 3 of 1.1 are the whole story: **an overlay that
covers the screen is the LAST child of its root.** That is where the options
menu, the name prompt and the create-lobby dialog already sit.

The same reasoning as 1.5 applies to a new one, with no bands worth naming: a
screen has a background, a body and its overlays, in that order.

### 1.8 What is NOT in the band system

- **Tooltips.** A tooltip goes through `Control._make_custom_tooltip`, and Godot
  draws it in the viewport's own tooltip popup, above every layer. It is already
  in front of everything and must never be hand-placed into the HUD to get it
  there. `CommandSlot` and `StatusIcon` are the worked examples.
- **Anything in the 3D world.** A health bar, a range circle, an order marker:
  those are drawn in the world and sorted by the renderer, not by this.

### 1.9 Checking it

Order is checkable without a human, and the check should be part of any change to
it - a screenshot alone cannot tell "correctly covered" from "never shown".

- **The order itself** is `get_index()` on the HUD's children. A headless run
  that prints them, and asserts the pairs that matter, proves the draw order by
  rule 3 of 1.1 without drawing a pixel.
- **The pixels need a windowed run.** `--headless` installs the dummy driver and
  a screenshot from one is blank. Run windowed and save
  `get_viewport().get_texture().get_image()` after ~30 frames, which is how long
  a Control tree takes to settle.
- **Shoot the BEFORE as well as the after.** A shot of the options menu with no
  tutorial board showing through proves nothing on its own: it looks identical
  whether the board is correctly behind it or was never shown. The first shot has
  to show the thing present. This is `CLAUDE.md`'s positive-control rule, reached
  through a screenshot.
- Both probes are scaffolding: write them under `Scripts/Dev` and `Scenes/Dev`,
  and delete them when the check is done.

---

## 2. Animation

How a Control is moved, faded, scaled or popped. **Every ruling here is binding
in the same way section 1's are**, because the two traps below produce a panel
that ends up in the wrong place or an animation that silently never runs, and
both read as a layout bug rather than as an animation one.

### 2.1 The animator COMPONENTS, not an AnimationPlayer

Animation in this project is a small `Node` under `Scripts/Components/` that
**animates its own PARENT**. `MoveAnimation2D`, `ScaleAnimation2D`,
`FadeAnimation2D` and `SizeAnimation2D` are the four that matter, with
`ScaleWiggleAnimation2D`, `FadePulse2D` and `FloatingNoiseAnimator2D` as
ready-made variations; the `*3D` ones next to them do the same job for units.

Reach for these rather than an `AnimationPlayer` or a hand-rolled tween:

- **The parent is the target**, taken in `_ready` with `get_parent()`, so a node
  is animated by giving it a child and nothing has to be wired up. A component
  whose parent is neither a `Node2D` nor a `Control` frees itself with an error.
- Several may sit on one node at once. Each owns its own tween and they animate
  different properties, so a fade, a slide and a scale run as one movement.
- They are plain `Node`s, so a `Container` ignores them: a component may be a
  direct child of an `HBoxContainer` without being laid out as a member of it.
- Their calls are COROUTINES. `await move.move_to(...)` returns when the tween
  finishes, which is what makes a sequence - tick, out, rewrite, in - read as the
  four lines it is. Calling one WITHOUT awaiting is also fine and runs it in the
  background; that is how three animators are started on the same frame and only
  the longest is awaited.
- `do_pop(start, peak, end, up, down)` on the scale and size ones is the
  overshoot used for anything arriving.

### 2.2 What a Container will take back

**A Container OWNS its children's `position` and `size`. It does not own their
`modulate` or their `scale`.**

A container writes position and size into every child when it SORTS, and it
sorts whenever its own size changes or a child's minimum size does - which a
label's text changing is. So:

- `FadeAnimation2D` and `ScaleAnimation2D` are always safe on a node inside a
  container. Nothing ever takes them back.
- `MoveAnimation2D` and `SizeAnimation2D` on a node inside a container are safe
  only while nothing makes it re-sort, and a sort will snap the node back
  wherever it had got to. **Write the text FIRST, let the sort happen, and only
  then move** - which is also why a panel should read its resting position off
  the node after a `process_frame` rather than assuming one.
- A node whose parent is NOT a container - a panel positioned by hand inside a
  plain `Control` - may be moved freely. `TutorialPanel` moves its board that
  way to step clear of the Research Center.

`TutorialPanel` is the worked example of both halves: the block carrying the
body and the task slides and fades as one, and the tick inside it is SCALED
rather than moved, because the tick sits in an `HBoxContainer` that would take a
move back the moment the label beside it changed.

### 2.3 A tween is paused with the node that owns it

A tween created by a node stops when that node is paused. Anything that must
animate while the world is HELD - a tutorial lesson panel, a menu over a paused
match - needs `process_mode = Node.PROCESS_MODE_ALWAYS` on the node that owns
the component, and it is the node's own mode that counts, not the panel's.
Children inherit by default, so setting it on the root of the panel covers the
components under it.

This is the failure that looks like nothing at all: the sequence runs, the
`await` never returns, and the panel sits on a half-finished state until the
world moves again.

### 2.4 Where the numbers live

Durations, distances and overshoots are PRESENTATION, so they are constants at
the top of the script that plays them rather than values in a `.tres` - the same
rule `CLAUDE.md` gives for placeholder sizes and UI offsets. A number worth
tuning from outside the code has not turned up yet; if one does, it belongs in a
config resource with the rest of the presentation settings.
