class_name ButtonSoundBinder
extends Node

## Gives every BaseButton in the project its click, hover and refusal sounds,
## without a single one of them being authored. Lives as AudioHub's own child.
##
## WHY AUTOMATIC. There are 58 buttons across 19 scenes and every interactive
## thing in the game is already a BaseButton - CommandSlot, TechSlot, UnitTile,
## SendTierButton, ControlGroupSlot and DraftOption all extend Button. Wiring
## them one at a time means 58 edits and a 59th button that gets forgotten with
## no error to show for it. Here it is one connection and nothing to remember.
## A button that wants to differ says so with a ButtonSounds child.
##
## HOW IT CATCHES THEM. SceneTree.node_added, which fires for every node
## entering the tree anywhere - so the 15 UI scenes instanced at runtime are
## caught on exactly the same path as the ones sitting in a .tscn, and a scene
## change needs no rescan.
##
## **That signal fires for EVERY node in the game, creeps and projectiles
## included**, which is worth being honest about in a project that has already
## paid for a per-unit cost hiding in a log call. The callback is one cast and
## an early return - tens of nanoseconds against a spawn that allocates a node -
## and it does no work at all for anything that is not a button. It stays
## acceptable only while it stays that shape: nothing that walks the tree,
## touches a resource or reads References belongs in _on_node_added.
##
## THE DISABLED CASE. A disabled Button emits no `pressed`, which is why the
## version this came from carried an invisible second Button to catch the click.
## It does still emit `gui_input`, measured on 4.7.2 - Control emits that signal
## before BaseButton's own handler makes its disabled early return, and
## `disabled` never changes mouse_filter. So the catcher is unnecessary, and so
## are the two methods that had to be called by hand whenever a button's
## disabled state changed, because nothing signals that.

## Marks a button as already wired. A node can leave the tree and come back -
## a menu page being shown again - and node_added fires each time.
const BOUND_META: StringName = &"audio_button_bound"

var _config: AudioConfig:
	get:
		return References.audio_config


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Autoloads are readied before the main scene, so ordinarily there is
	# nothing to find. A binder added later - or a --script run that built its
	# own tree first - would otherwise miss everything already standing.
	_bind_existing(get_tree().root)


func _bind_existing(node: Node) -> void:
	_on_node_added(node)
	for child: Node in node.get_children():
		_bind_existing(child)


func _on_node_added(node: Node) -> void:
	var button: BaseButton = node as BaseButton
	if button == null:
		return
	if button.has_meta(BOUND_META):
		return
	button.set_meta(BOUND_META, true)

	button.pressed.connect(_on_pressed.bind(button))
	button.mouse_entered.connect(_on_hovered.bind(button))
	button.gui_input.connect(_on_gui_input.bind(button))


# --- the three events ------------------------------------------------------

func _on_pressed(button: BaseButton) -> void:
	var marker: ButtonSounds = ButtonSounds.find_marker(button)
	if marker != null && !marker.use_click:
		return
	var config: AudioConfig = _config
	var path: String = config.ui_click_path if config != null else ""
	if marker != null && !marker.click_path.is_empty():
		path = marker.click_path
	AudioHub.play_ui(path)


func _on_hovered(button: BaseButton) -> void:
	# mouse_entered fires on a disabled button too, and a button that cannot be
	# pressed should not invite the press.
	if button.disabled:
		return
	var marker: ButtonSounds = ButtonSounds.find_marker(button)
	if marker != null && !marker.use_hover:
		return

	var config: AudioConfig = _config
	var path: String = config.ui_hover_path if config != null else ""
	if marker != null && !marker.hover_path.is_empty():
		path = marker.hover_path

	# Hover gets its own, much longer gap. A command card is a grid and one
	# mouse sweep crosses a dozen buttons inside a few frames; at the ordinary
	# same-sound gap that is a machine gun.
	var gap: float = config.budget_hover_gap if config != null else 0.06
	AudioHub.play_ui(path, gap)


## The refusal, and the only reason this connects to gui_input at all.
##
## Fires for motion as well as clicks, so the type check is first and is the
## whole cost for everything that is not a press.
func _on_gui_input(event: InputEvent, button: BaseButton) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null || !click.pressed:
		return
	# An ENABLED button's press is `pressed`'s job. Without this the two fire
	# together and every click in the game is doubled.
	if !button.disabled:
		return

	var marker: ButtonSounds = ButtonSounds.find_marker(button)
	if marker != null && !marker.use_refused:
		return
	var config: AudioConfig = _config
	var path: String = config.ui_refused_path if config != null else ""
	if marker != null && !marker.refused_path.is_empty():
		path = marker.refused_path

	# The same gap hover uses. A held mouse button on a card the player cannot
	# afford asks repeatedly, and so does an ability with repeat_on_hold.
	var gap: float = config.budget_hover_gap if config != null else 0.06
	AudioHub.play_ui(path, gap)
