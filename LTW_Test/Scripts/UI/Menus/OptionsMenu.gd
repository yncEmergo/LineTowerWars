class_name OptionsMenu
extends Control

## The options screen: four exclusive tabs over one stack of pages.
##
## Fullscreen and opaque, so it COVERS the game menu it was opened from rather
## than stacking a second panel on top of it. The key that backs out of it is
## still GameMenu's, for the reason its docstring gives: Escape peels one layer
## at a time and there is only ever one place that decides which layer is on top.
##
## PRESENTATION ONLY. Everything on it changes what this machine draws or hears
## and nothing it simulates, so a change applies the moment it is made and is
## written to disk right there. No Apply button and no Cancel, because there is
## nothing to roll back and nothing a server would have to agree to.
##
## Both rows of choices and the tab strip read their answer off the POSITION of
## the button pressed, the same way the command card reads a hotkey off the slot
## it sits in: the buttons of a row are authored in enum order and the index of
## the one pressed IS the value. A new choice is a new button and a new enum
## entry, and no wiring at all.

## Emitted when the screen closes itself - the Back button, or Escape arriving
## through GameMenu. Whoever opened it puts focus back where it belongs.
signal closed

@export_group("References")
## One Button per page, in page order, sharing a ButtonGroup.
@export var _tab_row: BoxContainer
## The pages, in tab order. Exactly one is visible at a time.
@export var _page_stack: Container
## Windowed / Windowed Fullscreen / Fullscreen, in UserSettings.WindowMode order.
@export var _window_mode_row: BoxContainer
## Always / Only when damaged / Never, in HealthBarDisplay order.
@export var _health_bar_row: BoxContainer
## Silences everything at once, independently of the six levels.
@export var _mute_button: BaseButton
@export var _back_button: Button


func _ready() -> void:
	hide()

	_connect_row(_tab_row, _on_tab_pressed)
	_connect_row(_window_mode_row, _on_window_mode_pressed)
	_connect_row(_health_bar_row, _on_health_bar_pressed)

	if _mute_button != null:
		_mute_button.toggled.connect(_on_mute_toggled)
	if _back_button != null:
		_back_button.pressed.connect(close)

	_select_page(0)


func open() -> void:
	if visible:
		return
	_sync_from_settings()
	show()
	_focus_active_tab()


func close() -> void:
	if !visible:
		return
	release_focus()
	hide()
	closed.emit()


## Wires every child button of a row to one handler, handing it the child's
## index. The row is the authority on which value is which, so nothing has to
## name a button.
func _connect_row(row: BoxContainer, handler: Callable) -> void:
	if row == null:
		Log.err("OptionsMenu is missing one of its choice rows, it will not answer")
		return
	var index: int = 0
	for child: Node in row.get_children():
		var button: BaseButton = child as BaseButton
		if button != null:
			button.pressed.connect(handler.bind(index))
			index += 1


## Writes what is stored onto the controls, without any of them reporting the
## write back as a player choice: setting button_pressed does not emit pressed.
func _sync_from_settings() -> void:
	_press_in_row(_window_mode_row, int(UserSettings.window_mode))
	_press_in_row(_health_bar_row, int(UserSettings.health_bar_display))
	if _mute_button != null:
		_mute_button.set_pressed_no_signal(UserSettings.audio_muted)


## Every button in the row is unpressed by hand before the chosen one is
## pressed, and that is forced rather than tidy: set_pressed_no_signal does not
## walk the ButtonGroup the way a real press does, so leaving it to the group
## shows two buttons lit at once.
func _press_in_row(row: BoxContainer, index: int) -> void:
	if row == null:
		return
	var buttons: Array[BaseButton] = _buttons_of(row)
	if index < 0 || index >= buttons.size():
		Log.err("OptionsMenu has no button for a stored setting", index)
		return
	for button: BaseButton in buttons:
		button.set_pressed_no_signal(false)
	buttons[index].set_pressed_no_signal(true)


func _buttons_of(row: BoxContainer) -> Array[BaseButton]:
	var buttons: Array[BaseButton] = []
	for child: Node in row.get_children():
		var button: BaseButton = child as BaseButton
		if button != null:
			buttons.append(button)
	return buttons


func _on_tab_pressed(index: int) -> void:
	_select_page(index)


## Shows the page at a tab's index and hides the rest. The two lists are kept
## in the same order by hand, and a mismatch is worth saying out loud rather
## than leaving the screen blank.
func _select_page(index: int) -> void:
	if _page_stack == null:
		Log.err("OptionsMenu has no page stack, it has nothing to show")
		return

	var pages: Array[Node] = _page_stack.get_children()
	if index < 0 || index >= pages.size():
		Log.err("OptionsMenu was asked for a page it does not have", {
			"index": index,
			"pages": pages.size(),
		})
		return

	for page_index: int in range(pages.size()):
		var page: CanvasItem = pages[page_index] as CanvasItem
		if page != null:
			page.visible = page_index == index


func _on_window_mode_pressed(index: int) -> void:
	UserSettings.set_window_mode(index as UserSettings.WindowMode)


## The one setting on this screen with something live behind it. Bars created
## after this point read the new value themselves; the ones already standing in
## the world are told, which is the whole reason HealthBar3D keeps a group.
func _on_health_bar_pressed(index: int) -> void:
	UserSettings.set_health_bar_display(index as UserSettings.HealthBarDisplay)
	get_tree().call_group(HealthBar3D.GROUP, "refresh_visibility")


func _on_mute_toggled(pressed: bool) -> void:
	UserSettings.set_audio_muted(pressed)


## Focus lands on the tab that is open rather than on the first control of the
## page, so the arrow keys walk the tabs the way the mouse does.
func _focus_active_tab() -> void:
	if _tab_row == null:
		return
	for button: BaseButton in _buttons_of(_tab_row):
		if button.button_pressed:
			button.grab_focus()
			return
