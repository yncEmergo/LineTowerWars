class_name TutorialExplainStep
extends TutorialStep

## A short EXPLANATION, one page at a time: the world held, everything dimmed
## but a panel in the middle of the screen and the one HUD element the page is
## about, framed and captioned. Continue turns the page.
##
## For the few things that are read off the HUD rather than done - what the
## numbers at the top of the screen mean. A task teaches better than a page
## wherever there is something to DO, so reach for this last and keep it to a
## handful of pages.
##
## Finished once every page has been read. It holds the world by its nature,
## so validate() refuses one that does not.

@export_group("Pages")
@export var pages: Array[TutorialPage] = []


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.pages_read() >= pages.size()


## The page up now, or null once they are all read.
func page_at(index: int) -> TutorialPage:
	if index < 0 || index >= pages.size():
		return null
	return pages[index]


func validate() -> bool:
	var complete: bool = super()
	if pages.is_empty():
		Log.err("An explanation has no pages", resource_path)
		complete = false
	for page: TutorialPage in pages:
		if page == null || !page.validate(resource_path):
			complete = false
	if !pauses_world:
		Log.err("An explanation does not hold the world, the match would run on under it",
			resource_path)
		complete = false
	return complete
