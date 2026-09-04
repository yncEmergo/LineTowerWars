# Archive

**Working code that was replaced, kept because it worked.**

Nothing here is part of the game. A `.gdignore` keeps Godot's filesystem out of this
folder entirely, so nothing in it is imported, no `class_name` in it reaches the global
class cache, and none of it costs anything at load time. It is source kept for reading and
for restoring, not source that runs.

## What belongs here

Code that **did its job and was superseded by an architectural change** — not code that was
wrong. That distinction is the whole point of the folder:

- a system that was **correct but too expensive** for where it had to run
- a system replaced because the surrounding architecture changed underneath it
- an approach that was measured, worked, and lost to a different trade

**A bug fix does not go here.** Neither does an experiment that failed — git already holds
both, and a folder full of things that never worked is a folder nobody reads.

## What does NOT belong here

- anything git alone answers: an old revision of a file that still exists
- dead code nobody chose to delete. Delete it
- scaffolding. `Scripts/Dev` is scaffolding and is deleted outright

## The rule for adding something

One folder per archived system, named for it and dated. Inside it:

1. **the files, at the revision they were last working**, in their original folder shape,
   so the paths in them still read correctly
2. **a `README.md`** answering four questions, and none of them optionally:
   - **What was it?** One paragraph.
   - **Why was it replaced?** The real reason, including what it was GOOD at. This is the
     part that matters and the part that is always missing a year later.
   - **What replaced it?**
   - **What would have to be true to want it back?** The condition under which somebody
     should read this again, stated concretely enough to recognise.
3. **the commit it was taken from**, so the surrounding code of that day can be read too

The fourth question is the one that earns the folder. Archiving without it produces a
museum; archiving with it produces a decision somebody can revisit.

## What is in here

Nothing yet. The folder and this policy were written before the first archival rather than
after it, so that the first one has a shape to follow.

**Expected first entry: the server-authoritative replication layer** (`ReplicationService`
and what reads its snapshots), if and when the lockstep cutover lands — see
`Docs/lockstep-migration.md` and `Docs/multiplayer.md` §4.1. It is the worked example of
what this folder is for: it **worked correctly**, and the thing it lost to was the CPU cost
of simulating every lane centrally on a rented box, not a fault in it. If player counts,
hosting budget or per-unit cost ever move, it becomes the right answer again.
