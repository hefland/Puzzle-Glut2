extends Node
## InputHub — tracks which input device the player used last (touch, mouse &
## keyboard, or gamepad) so the HUD can swap button prompts and on-screen
## touch controls automatically, and makes sure menus always have a focused
## control when a gamepad is in use.

signal device_changed(device: String)

const TOUCH := "touch"
const KBM := "kbm"
const PAD := "pad"

var device: String = KBM


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile"):
		device = TOUCH
	if Input.get_connected_joypads().size() > 0 and not OS.has_feature("mobile"):
		device = PAD


func _input(event: InputEvent) -> void:
	var d := ""
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		d = TOUCH
	elif event is InputEventJoypadButton:
		if event.pressed:
			d = PAD
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.55:
			d = PAD
	elif event is InputEventKey:
		if event.pressed:
			d = KBM
	elif event is InputEventMouseButton:
		# Mouse events emulated from touch carry the emulation device id.
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.pressed:
			d = KBM
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.relative.length() > 6.0:
			d = KBM
	if d != "" and d != device:
		device = d
		device_changed.emit(device)
		if device == PAD:
			ensure_focus()


func is_touch() -> bool:
	return device == TOUCH


func is_pad() -> bool:
	return device == PAD


## If nothing has focus, focus the first visible focusable control on screen.
func ensure_focus() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var current := vp.gui_get_focus_owner()
	if current and current.is_visible_in_tree():
		return
	var best := _find_focusable(get_tree().current_scene)
	if best:
		best.grab_focus()


func _find_focusable(node: Node) -> Control:
	if node == null:
		return null
	# Prefer controls inside the top-most visible modal overlay group.
	var overlays := get_tree().get_nodes_in_group("modal_overlay")
	for o in overlays:
		if o is CanvasItem and o.is_visible_in_tree():
			var c := _first_focusable(o)
			if c:
				return c
	return _first_focusable(node)


func _first_focusable(node: Node) -> Control:
	if node is Control and node.focus_mode == Control.FOCUS_ALL and node.is_visible_in_tree():
		if not (node is BaseButton and node.disabled):
			return node
	for child in node.get_children():
		var c := _first_focusable(child)
		if c:
			return c
	return null


## Short prompt text for the given logical action on the active device.
func prompt(action: String) -> String:
	var table := {
		KBM: {"move": "←/→", "rotate": "W / Z", "soft": "S", "hard": "Space", "ability": "E", "accept": "Enter", "back": "Esc", "pause": "Esc"},
		PAD: {"move": "D-Pad", "rotate": "Ⓐ / Ⓑ", "soft": "LT", "hard": "RT / ▲", "ability": "Ⓧ / Ⓨ", "accept": "Ⓐ", "back": "Ⓑ", "pause": "Start"},
		TOUCH: {"move": "Swipe", "rotate": "⟳", "soft": "▼", "hard": "Flick ▼", "ability": "Tap ★", "accept": "Tap", "back": "Back", "pause": "Ⅱ"},
	}
	return str(table.get(device, table[KBM]).get(action, action))
