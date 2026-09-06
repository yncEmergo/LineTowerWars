class_name BuildInfo
extends Resource

## What this build IS: the stage the project is at, and when the build was made.
##
## Stored as Resources/Config/build_info.tres, reached via References.build_info.
## Shown in the corner of the main menu, and written into the header of a session
## log, so a report that comes back names the build it came from.
##
## ## The stamp is deliberately empty in git
##
## `stage` is AUTHORED and is the only field here a human ever sets. `built_at`
## and `commit` are STAMPED by Tools/build_client.ps1 immediately before the
## export and restored immediately after, so the committed file always reads
## empty and a build stamp never turns up in a diff.
##
## An empty stamp is MEANINGFUL rather than missing: it is exactly what a run
## from the editor is, and the label says so rather than inventing a date. That
## is also why the stamp is not simply written once and committed - a date in
## git would be the date somebody last edited the file, which is a different
## fact wearing the same clothes.
##
## ## Why the game carries this at all, rather than reading its own exe
##
## Godot does write application/file_version into the Windows PE header at
## export, and nothing at runtime can read it back. A resource inside the pack
## is the only way the running game can say which build it is - and it is the
## only way that works the same on a platform with no PE header at all.
##
## ## The script defaults are empty ON PURPOSE
##
## The .tres is the authority for `stage`. Saving a resource from the editor
## drops every property that equals its script default (CLAUDE.md), so a default
## of "prototype" here would be silently stripped from the file on the next save
## and the real value would quietly move into this script. Empty defaults keep
## the data in the file that is supposed to hold it.

## Separator between the parts of the label. A formatting detail, so it lives
## here rather than in the resource.
const SEPARATOR: String = " · "

## What the stamp reads as when there is none - an editor run, or an export made
## without the build script. Named rather than inlined so the two readers of it
## cannot drift apart.
const DEV_BUILD_TEXT: String = "dev build"

@export_group("Authored")
## Where the project is in its life: prototype, alpha, beta, release. The one
## field here a human sets, and it changes when the PROJECT does rather than
## when a build is made.
@export var stage: String = ""

@export_group("Stamped at build time")
## When this build was exported, as "YYYY-MM-DD HH:MM" in UTC.
##
## UTC rather than local time, for two reasons that both bite: a report comes
## back from whichever timezone the tester is in, and two builds made the same
## afternoon on the two dev machines have to be orderable against each other.
@export var built_at: String = ""

## The short commit this build was made from.
##
## This is the field that actually closes a bug report. A date says WHICH BUILD,
## a commit says WHICH CODE - and only the second one can be checked out and
## run again.
@export var commit: String = ""


## Whether this is a real export rather than an editor run or an unstamped one.
func is_stamped() -> bool:
	return !built_at.strip_edges().is_empty()


## The one line shown in the corner of the menu, and written into a session log.
##
## Reads "prototype · dev build" from the editor, and
## "prototype · 2026-09-06 12:34 UTC · a1b2c3d" from a build.
##
## Every part is dropped when it is empty rather than left as a dangling
## separator, so a half-filled resource still produces a sentence.
func label_text() -> String:
	var parts: PackedStringArray = PackedStringArray()

	var stage_text: String = stage.strip_edges()
	if !stage_text.is_empty():
		parts.append(stage_text)

	if !is_stamped():
		parts.append(DEV_BUILD_TEXT)
		return SEPARATOR.join(parts)

	parts.append(built_at.strip_edges())

	var commit_text: String = commit.strip_edges()
	if !commit_text.is_empty():
		parts.append(commit_text)

	return SEPARATOR.join(parts)
