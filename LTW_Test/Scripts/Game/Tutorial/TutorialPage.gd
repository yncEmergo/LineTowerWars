class_name TutorialPage
extends Resource

## One page of an explanation: a few words in the middle of the screen, and the
## HUD element they are about, framed and named with a short caption.
##
## A sub-resource of the TutorialExplainStep that owns it, in the same .tres.
## Shared and stateless like the step: which page is up is TutorialDirector's.

@export_group("Settings")
## What the page says, in the panel in the middle of the screen.
@export_multiline var text: String = ""
## The HUD element it is about, by the same names TutorialPointer knows - see
## highlight_key on TutorialStep.
@export var highlight_key: StringName = &""
## The short label drawn beside that element - "Your current gold".
@export var caption: String = ""


func validate(lesson: String) -> bool:
	if text.is_empty():
		Log.err("A tutorial page says nothing", lesson)
		return false
	return true
