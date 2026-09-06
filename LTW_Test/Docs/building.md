# Making a build

How a playable client is exported and handed to a tester. **Procedure only** — what the
networked build *is* is `multiplayer.md`, and how to run the server it dials is `server.md`.

There is one preset and one target: **Windows desktop, x86_64, release**. The server is not
exported at all — it runs from a git checkout on the rented machine (`server.md`), so nothing
here produces one.

---

## Before the first build on a machine

**Export templates have to be installed, and their version has to match the editor exactly.**
A mismatch is refused with a message naming both. They are not part of the repo — they are
per-machine, like the editor itself, and this project is developed on more than one PC.

The editor installs them from *Editor → Manage Export Templates → Download and Install*. That
is the normal way and needs nothing else.

By hand, if the editor is not open: the archive is
`Godot_v<version>-stable_export_templates.tpz` from Godot's own release page, and it unpacks
into `templates/`. That folder's contents go to `%APPDATA%\Godot\export_templates\<version>\`,
where `<version>` is the string inside the archive's own `version.txt` — copy it from there
rather than typing it, because the folder name has to match it character for character.

Check which editor the templates have to match with `& $env:GODOT --version`. Setting `GODOT`
once per machine is in `server.md`.

---

## The build itself

From the project root:

```powershell
.\Tools\build_client.ps1            # stamp, export, restore
.\Tools\build_client.ps1 -Zip       # and zip the result for upload
```

It writes beside the project, into `..\Builds\Windows\`, which is **outside the Godot project
on purpose**: an exe or a pck sitting in the project tree is something Godot's filesystem
would try to take an interest in. It is git-ignored from the repository root.

The script refuses to build from a tree with uncommitted changes, because the stamp it writes
names a commit — and a stamp naming a commit the build does not actually contain is worse than
no stamp at all, since it makes a bug report point at the wrong code with total confidence.
`-Force` overrides that for a throwaway build.

### What the stamp is, and why a script has to do it

`Resources/Config/build_info.tres` carries the stage word, the build time in UTC and the short
commit. The game shows all three in the corner of the main menu and writes them into the header
of a session log, so a report that comes back names the build it came from.

The script writes the stamp immediately before the export and restores the file byte for byte
immediately afterwards, in a `finally`, so the committed resource always reads empty and a
build stamp never appears in a diff. An empty stamp is meaningful rather than missing: it is
what an editor run is, and the label reads `dev build` instead of inventing a date.

The stamp is INSERTED after the `script = ExtResource(...)` line rather than substituted into
existing lines, because the editor drops any property equal to its script default when it saves
a `.tres` — so `built_at` and `commit` may not be in the file to substitute into.

### Two Windows traps this script is built around

Both cost a build on 2026-09-06, and both produced a **stale build reported as a fresh one**,
which is the failure worth recognising rather than either mechanism.

**`& $godot` does not wait.** The editor binary is a Windows GUI-subsystem executable, so
PowerShell starts it and carries straight on: the call returns before the export has written a
byte, `$LASTEXITCODE` is never set from it, and its output goes to the console rather than down
the pipeline. The stamp was restored while Godot was still starting, and the script then listed
the previous build's files and called it a success. `Start-Process -Wait -PassThru` waits
properly and yields a real exit code.

**`Start-Process` does not quote for you.** An argument holding a space arrives split in two,
and both of the ones here hold one — the project path and the preset name. The call operator
had been quoting them silently, so this only appeared once the launch moved to `Start-Process`.

So the script **asserts the effect rather than the command**: it checks the pack is newer than
the moment the export started, exactly as `deploy_server.ps1` compares the service pid rather
than trusting that `systemctl restart` ran.

Three files come out — the game, a console wrapper, and the pck. **All three go in the zip**;
the game will not start without the pck beside it.

The console wrapper is the second exe. It is the same game with a terminal attached, and it is
there so a tester who is asked for output has something to double-click. Nobody needs to run
it otherwise.

### It exports cleanly with the editor open

The export is a separate headless process reading the files from disk, so it does not need the
editor closed and does not care what the editor has in memory. The one thing to watch is that
an open editor **rewrites `export_presets.cfg` when it saves its own copy** — the same trap
`CLAUDE.md` records for hand-written scenes. Re-check the file afterwards if the export dialog
was opened.

---

## Deploy the server FIRST, and build from the same commit

**The build and the server must be the same commit, and the server deploys from git.** So the
order is: commit, push, `.\Tools\deploy_server.ps1`, and only then export. Building first and
deploying afterwards works too, as long as nothing is edited in between — what must never
happen is handing out a build from code the server has never seen.

The handshake catches the case that matters: two builds whose `@rpc` sets differ are refused at
connect time with a message naming both, rather than being let in to misroute calls
(`server.md`). It does **not** catch a difference that only affects the simulation, and under
lockstep every client simulates — so two clients on different commits are a desync waiting for
a reason. One build, handed to everybody, is what keeps that from being a question.

`.\Tools\deploy_server.ps1 -Check` prints all three — server, origin, and your working tree —
and warns when they have parted. Check it before a test, not after one has gone wrong.

---

## What is in the build, and what is deliberately not

Excluded by the preset's filter:

- **`addons/godotsteam`** — a GDExtension nothing calls yet. Shipping it would put a
  `steam_api` DLL next to the game as a startup dependency, in exchange for nothing, and a
  missing or blocked one fails at load rather than politely. It stays in the repo for the day
  it is used; the filter is the line to remove.
- **`ReferenceFilesFromOtherProjects`** — reference material from elsewhere, imported by
  Godot because only its `SteamLobbyTemplate` subfolder carries a `.gdignore`. None of it is
  reachable from the game, and none of it is ours to hand out.

Non-resources are not exported at all, so the docs, `CLAUDE.md` and everything under `Tools/`
stay out without being named in a filter.

**`addons/godot_ai` DOES ship**, and this is deliberate rather than an oversight. It registers
an autoload in `project.godot`, so excluding its files would leave the autoload pointing at a
script that is not there, which fails at boot. The addon is written to sit idle when the
editor-debugger channel is inactive, which is exactly what an exported build is. The honest
way to remove it is to disable the plugin so it withdraws its own autoload — worth doing for a
public release, not worth the risk before a closed test.

### The feature tag decides what the process is

`Boot` asks `OS.has_feature("dedicated_server")`, so **the client preset must never set
`dedicated_server`** — a build carrying that tag opens the server scene and never shows a menu.

`OS.has_feature("template")` is the other one the game reads: it is true in an export and
false in every way the project is run during development, and `NetworkConfig` uses it to drop
the loopback address a handed-out build could never reach. Both are proven the same way, by
exporting and running the thing, because neither branch is reachable from the editor.

---

## Known gaps

- **No application icon.** The build wears Godot's. Setting `application/icon` in the preset to
  a square PNG in the repo is all it takes, once there is one to point at.
- **The stage word is set by hand.** `stage` in `build_info.tres` says `prototype`; nothing
  moves it to `alpha` but somebody deciding it has. That is the intent — it tracks where the
  project is, not when a build was made — but it will be wrong for a while after it changes.
