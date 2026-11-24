class_name HubPanel
extends Node3D

## The hub in the headset (#1071, CRW-2, CRF-3, CRF-4): the current page's
## lines, the selected row marked and coloured, and a refused press's reason
## under the page. The pilot drives it like the dev menu: right stick up and
## down moves the row, left and right turns the page, A presses. Hung under the
## rig origin at the head point like `ShaftPanel`, and drawn over the fade quad
## the same way. Since #1299 the pages are on the home base room's stations
## (`HubStations`); the panel shows only when the room fails to load.
##
## The lines and the actions come from a hub text (`meta/hub_text.gd`). `xr/`
## may not depend on `meta/` (the layer table in `CLAUDE.md`), so the panel
## names no meta class: it is handed any object with the hub text's methods
## (`HUB_METHODS`) and calls them by name. A press acts only through that
## object, which changes the profile and the fitting; the panel itself writes
## no simulation state (MP-2), reads no comfort setting (ARC-3), and moves or
## animates nothing (CMF-8). Size, colours and placement come from
## `HubPanelLook` (ARC-4).

const NODE_NAME: String = "HubPanel"
const LINE_PREFIX: String = "Line"
## The hub text's methods the panel calls.
const HUB_METHODS: Array[String] = ["lines", "selected_line", "selected", "press", "move", "turn_page"]
## The dev menu's named actions, so the wiring maps the same buttons to both.
const ACTIONS: Array[String] = [DevMenuModel.UP, DevMenuModel.DOWN, DevMenuModel.LEFT, DevMenuModel.RIGHT,
	DevMenuModel.CONFIRM]
const ROW_STEPS: Dictionary[String, int] = {DevMenuModel.UP: -1, DevMenuModel.DOWN: 1}
const PAGE_STEPS: Dictionary[String, int] = {DevMenuModel.LEFT: -1, DevMenuModel.RIGHT: 1}

var hub: Object = null
var _look: Dictionary
var _lines: Array[Label3D] = []
var _reason: Label3D
var _held: Dictionary = {}


func _init(look: Dictionary = HubPanelLook.load_file()) -> void:
	name = NODE_NAME
	_look = look
	_reason = _label("Reason", look["reason_font_size"])
	_reason.modulate = look["reason_color"]
	_reason.visible = false
	visible = false


## Shows `p_hub`, an object with every method in `HUB_METHODS`. A button held
## while the panel opens counts only once it is let go and pressed again, so
## the press that opened the panel cannot also act in it.
func open(p_hub: Object) -> void:
	for method: String in HUB_METHODS:
		assert(p_hub.has_method(method), "the hub panel needs a hub text with %s()" % method)
	hub = p_hub
	_held = {}
	for action: String in ACTIONS:
		_held[action] = true
	_reason.text = ""
	visible = true
	_refresh()


## Hides the panel; the hub text keeps its page and row for the next `open`.
func close() -> void:
	visible = false


## One frame of named actions (see `DevMenuModel.press`): each counts once, on
## the frame it is pressed, never while held, and the first one pressed wins
## the frame. A press of A returns {"pressed": <the hub text's selected()>,
## "reason": <its press() result>}; every other frame returns {}. Closed, the
## panel ignores input.
func update(held: Dictionary) -> Dictionary:
	if not visible or hub == null:
		return {}
	var acted: String = ""
	for action: String in ACTIONS:
		var down: bool = bool(held.get(action, false))
		if down and not bool(_held.get(action, false)) and acted == "":
			acted = action
		_held[action] = down
	if acted == "":
		return {}
	_reason.text = ""  # Any input clears the last refusal.
	var result: Dictionary = {}
	if ROW_STEPS.has(acted):
		hub.call("move", ROW_STEPS[acted])
	elif PAGE_STEPS.has(acted):
		hub.call("turn_page", PAGE_STEPS[acted])
	else:
		var picked: Dictionary = hub.call("selected")
		var reason: String = hub.call("press")
		_reason.text = reason
		result = {"pressed": picked, "reason": reason}
	_refresh()
	return result


## The text of each shown line, the title first and the selected row marked.
func texts() -> Array[String]:
	var shown: Array[String] = []
	for line: Label3D in _lines:
		if line.visible:
			shown.append(line.text)
	return shown


## The refused press's reason under the page, or "" when none is shown.
func reason_text() -> String:
	return _reason.text if _reason.visible else ""


## One label per line of the hub text's page; labels past the page are hidden
## and kept for a longer page.
func _refresh() -> void:
	var page: Array[String] = []
	page.assign(hub.call("lines"))
	var chosen: int = hub.call("selected_line")
	while _lines.size() < page.size():
		_lines.append(_label("%s%d" % [LINE_PREFIX, _lines.size()], _look["line_font_size"]))
	var top: Vector3 = _look["title_position_m"]
	var step: Vector3 = Vector3(0.0, -float(_look["line_step_m"]), 0.0)
	for i: int in _lines.size():
		var line: Label3D = _lines[i]
		line.visible = i < page.size()
		if not line.visible:
			continue
		var text: String = page[i]
		var color: Color = _look["text_color"]
		if i == 0:
			color = _look["title_color"]
		elif i == chosen:
			text = _look["mark_text"] + text
			color = _look["selected_color"]
		if line.text != text:
			line.text = text  # Label3D rebuilds its glyphs on every assignment.
		line.font_size = roundi(float(_look["title_font_size"] if i == 0 else _look["line_font_size"]))
		line.position = top + step * i
		line.modulate = color
	_reason.visible = _reason.text != ""
	_reason.position = top + step * page.size()


func _label(label_name: String, font_size: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.pixel_size = _look["pixel_size"]
	label.font_size = roundi(font_size)
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DestroyedScreen.RENDER_PRIORITY
	label.layers = 1 | HubRoom.LAYER_BIT  # Also drawn while the camera shows only the hub room (#1298).
	add_child(label)
	return label
