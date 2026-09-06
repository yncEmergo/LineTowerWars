# Docs

Every reference document for this project except the two that have to sit in the root:
`CLAUDE.md`, which Claude Code loads by name, and `README.md`, which a git host renders.

Each file is the authority on its own subject. Where two disagree, the more specific wins.

## Which file answers what

| File | Answers |
| --- | --- |
| [game_rules.md](game_rules.md) | **The RULES.** How the game works — economy, mazing, sending, damage resolution, lives, win condition, and the visual language the rosters are built to. Says which rules are BUILT and which are only written down. Carries no numbers; points at `unit_data.md` instead. |
| [unit_data.md](unit_data.md) | **The NUMBERS.** Every tower, creep, disc and technology of Warcraft III Line Tower Wars 12.4a, whose balance the prototype copies. Costs, stats, upgrade paths, tech requirements. |
| [content.md](content.md) | **The PROCEDURE.** How a tower, creep, disc or ability is actually added or changed: which files it is made of, which of them are generated, how an id is picked, and what refuses bad content at boot. Carries no rules and no numbers. |
| [multiplayer.md](multiplayer.md) | **The networked build.** What it is, where each part lives, the decisions behind it, and the costs deliberately not paid yet. |
| [multiplayer-todo.md](multiplayer-todo.md) | **What the networked build still needs**, in the order it is worth doing - and the long view on getting input latency below the raw ping between players on different continents. A plan, not a record. |
| [audio.md](audio.md) | **The audio build.** The bus layout and the settings seam, AudioHub and the voice budget, how every button gets its sound without being authored, and where a sound is named. Architecture only; the levels and caps live in `audio_config.tres`. |
| [building.md](building.md) | **Making a build.** How a playable client is exported and handed to a tester: the export templates a machine needs first, the one command, what the preset leaves out and why, and the rule that the server is deployed from the same commit. Procedure only. |
| [server.md](server.md) | **Server controls.** How to start, stop and aim the dedicated server, and how two PCs in different places reach each other to test. Controls only, never architecture — that is `multiplayer.md`. |
| [Findings/](Findings/) | **Investigations.** Something that was measured, dug into or ruled out, written up and dated. |
| `../CLAUDE.md` | Conventions, engine traps, hard rules. In the root because Claude Code loads it from there. |
| `../README.md` | The way in: what the project is, what works today. In the root because that is where a git host looks. |

## Where a new document goes

Ask what kind of thing it is, in this order:

1. **A rule about how the game works** → into `game_rules.md`. Not a new file.
2. **A number the design decides or copies from LTW 12.4a** → into `unit_data.md`. Not a new file.
3. **Something about the networked build** → into `multiplayer.md` if it is BUILT, into
   `multiplayer-todo.md` if it is not.
4. **A control the server gained or lost** → into `server.md`, and keep it current.
   **A step in exporting or handing out a build** → into `building.md`, on the same terms.
5. **A convention, or a trap the engine set that cost a debugging session** → into `../CLAUDE.md`.
6. **A step in authoring or changing content** — which file to edit, what is generated,
   what checks it → into `content.md`. Not a new file, and not a rule: anything about what
   the content should DO belongs in `game_rules.md` instead.
7. **An investigation** — measured something, chased a bug, ruled an approach out → a new
   file in [Findings/](Findings/). This is the only kind of document that gets its own file
   without asking, because it is a record of one piece of work rather than a living
   reference.

Anything that does not fit those seven probably belongs as a comment next to the code it is
about. This project keeps its explanation in the source deliberately: a docstring moves when
the code moves, and a paragraph in an .md does not.

## The two rules that bite hardest

Both are stated in full in `../CLAUDE.md`; they are repeated here because this is the folder
where they get broken.

**No counts, and no live values.** Not "26 abilities", not "the tick budget is 50 ms", not a
stat quoted out of a `.tres`. They are true for a day and misleading afterwards, and nothing
ever updates them. Write the mechanism, the rule and the authored id instead — those are
durable. `game_rules.md` and `unit_data.md` are the only exceptions, and only for values they
DECIDE or COPY FROM THE SOURCE GAME.

`Findings/` is the third exception, and a narrow one: a finding is a DATED measurement, so its
numbers are a snapshot of one day on one machine rather than a claim about now. See its README.

**No hotkeys, and no card slots.** Not which letter an ability answers to, not which square it
claims. The `.tres` is the single source of truth for both. The RULE survives and is worth
writing — that the key is read off the position, that a passive never takes a square worth
pressing. The READING does not.

## Scripts

Not here. The control scripts live in [`../Tools/`](../Tools/) and are typed from the project
root: `.\Tools\run_server.ps1`, `.\Tools\stop_server.ps1`, `.\Tools\run_bench.ps1`.
`server.md` documents the first two, and `Findings/` the third. Exporting the game is not a script
in there at all — it is one `godot --export-release` line, written out in `building.md`.
