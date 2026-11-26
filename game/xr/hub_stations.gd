class_name HubStations
extends Node3D

## The hub's pages on the stations of the home base room (#1299, CRW-2, CRF-3,
## CRF-4, RUN-8, decision record 0012), in place of the flat `HubPanel`. The
## pilot first chooses a station: the right stick left and right steps through
## them in the room's order and wraps, and pointing the right controller's aim
## at one highlights it; A uses the highlighted station. Inside it the stick up
## and down moves the row and A presses it, as on the panel; stick left goes
## back to choosing a station. Every press is a dev menu named action (decision
## record 0009), so the controls stay remappable (PLT-5).
##
## The station in use shows the hub text's window of its rows and the selected
## row's note (#1300), from the hub text (`meta/hub_text.gd`, chosen with its
## `choose_station`), so the stations and the panel share one copy of the hub's
## rules; the others show only their title. Like the panel it
## names no meta class and calls the hub text by method name (`HUB_METHODS`),
## writes no simulation state (MP-2), reads no comfort setting (ARC-3) and
## moves no camera (CMF-8): only the screen in use comes towards the eye and
## grows, so its rows can be read (#1359, `HubStationScreen`). The screens hang
## on the room's station meshes, so the room is read only to find them.
##
## A hub text may also draw on the station in use (`drawing`, `back`,
## `slot_at`, `point_slot`; #1366): the Fitting Bay shows its ship with slots
## (`HubFittingView`), stick left steps back from choosing an item to the ship
## before it leaves the station, and the aim picks a slot on the ship. The
## Workbench draws its tech tree the same way (`HubTreeView`, #1367) and the
## aim picks a node on it.

const NODE_NAME: String = "HubStations"
## The hub text's methods the stations call.
const HUB_METHODS: Array[String] = ["lines", "selected_line", "selected", "press", "move", "choose_station",
	"leave_station", "rows_shown", "first_shown", "note"]
## How far the aim ray may pass from a screen's centre and still point at it;
## the screens are 0.45 m apart, so two never both qualify.
const POINT_RADIUS_M: float = 0.2
## Longer than any screen takes to come forward or go back.
const SETTLE_SECONDS: float = 10.0

var hub: Object = null
## Station ids in the room's order, the order the stick steps through.
var ids: Array[String] = []
## Index into `ids` of the station that A would use.
var highlighted: int = 0
## The station in use, or "" while choosing.
var in_use: String = ""

var _labels: Dictionary[String, String] = {}
var _points: Dictionary[String, Vector3] = {}
var _screens: Dictionary[String, HubStationScreen] = {}
var _held: Dictionary = {}
var _reason: String = ""
var _pointed: String = ""
## The slot the aim was last on inside a station, as `_pointed` for stations.
var _pointed_slot: String = ""
var _room: HubRoom
var _screen_look: Dictionary = {}
var _icons: HubIcons
## Station id to its drawing (a `HubFittingView` or `HubTreeView`), made the
## first time the hub text draws there.
var _views: Dictionary[String, Node3D] = {}


## Puts a screen on each station of `room`; a room that was not built gives none.
func _init(room: HubRoom, look: Dictionary = HubPanelLook.load_file(),
		screen: Dictionary = HubScreenLook.load_file()) -> void:
	name = NODE_NAME
	visible = false
	_room = room
	_screen_look = screen
	if room == null or not room.is_built():
		return
	_icons = HubIcons.load_file()
	var points: Dictionary[String, Vector3] = room.station_points()
	for station: Dictionary in room.spec.stations:
		var id: String = station["id"]
		var mesh: Node3D = room.get_node_or_null("Station_%s/Screen" % id) as Node3D
		if mesh == null or not points.has(id):
			continue
		ids.append(id)
		_labels[id] = station["label"]
		_points[id] = points[id]
		_screens[id] = HubStationScreen.new(look, HubRoom.LAYER_BIT, screen)
		_screens[id].set_eye(HubScreenMeasure.in_space_of(mesh, room).affine_inverse() * Vector3.ZERO)
		mesh.add_child(_screens[id])


func _process(delta: float) -> void:
	advance(delta)


## Moves every screen `seconds` on towards where it is heading: the one in use
## forward, the others back.
func advance(seconds: float) -> void:
	for id: String in ids:
		_screens[id].advance(seconds)


## The screen on station `id`, or null.
func screen(id: String) -> HubStationScreen:
	return _screens.get(id, null)


func has_stations() -> bool:
	return not ids.is_empty()


## Shows `p_hub` (an object with every method in `HUB_METHODS`), choosing a
## station from the first. A button held while it opens counts only once let
## go and pressed again, so the press that opened the hub cannot act in it.
func open(p_hub: Object) -> void:
	for method: String in HUB_METHODS:
		assert(p_hub.has_method(method), "the hub stations need a hub text with %s()" % method)
	hub = p_hub
	hub.call("leave_station")
	in_use = ""
	highlighted = 0
	_reason = ""
	_pointed = ""
	_held = {}
	for action: String in HubPanel.ACTIONS:
		_held[action] = true
	visible = true
	_refresh()


func close() -> void:
	visible = false
	in_use = ""
	if hub != null:
		hub.call("leave_station")
	for id: String in ids:
		_screens[id].show_title(_labels[id], false)
	for drawn: Node3D in _views.values():
		drawn.visible = false
	advance(SETTLE_SECONDS)  # Reopened, every screen starts at rest.


func highlighted_id() -> String:
	return ids[highlighted] if has_stations() else ""


## One frame of named actions, as `HubPanel.update`: each counts once, on the
## frame it is pressed, and the first one pressed wins the frame. A press of A
## inside a station returns {"pressed": <the hub text's selected()>, "reason":
## <its press() result>}; every other frame returns {}.
func update(held: Dictionary) -> Dictionary:
	if not visible or hub == null or not has_stations():
		return {}
	var acted: String = ""
	for action: String in HubPanel.ACTIONS:
		var down: bool = bool(held.get(action, false))
		if down and not bool(_held.get(action, false)) and acted == "":
			acted = action
		_held[action] = down
	if acted == "":
		return {}
	_reason = ""  # Any input clears the last refusal.
	var result: Dictionary = {}
	if in_use == "":
		_choose(acted)
	elif HubPanel.ROW_STEPS.has(acted):
		hub.call("move", HubPanel.ROW_STEPS[acted])
	elif acted == DevMenuModel.LEFT:
		if not (hub.has_method("back") and hub.call("back")):
			in_use = ""  # Back to choosing, on the station just left.
			hub.call("leave_station")
	elif acted == DevMenuModel.CONFIRM:
		var picked: Dictionary = hub.call("selected")
		_reason = hub.call("press")
		result = {"pressed": picked, "reason": _reason}
	_refresh()
	return result


## The aim ray in the room's space, from `origin` along `direction`, while
## choosing: the station it newly points at becomes the highlighted one, so a
## still hand does not undo a stick step. Returns the station pointed at, or "".
## Inside a station that draws a ship, it picks the slot it points at instead
## and returns that slot.
func point(origin: Vector3, direction: Vector3) -> String:
	if visible and in_use != "":
		return _point_in_station(origin, direction)
	if not visible:
		return ""
	var id: String = pick(origin, direction, _points, POINT_RADIUS_M)
	if id != _pointed and id != "":
		highlighted = ids.find(id)
		_refresh()
	_pointed = id
	return id


## The station whose point the ray passes nearest, within `radius` and in
## front of `origin`; "" when none does.
static func pick(origin: Vector3, direction: Vector3, points: Dictionary[String, Vector3], radius: float) -> String:
	if direction.length() < 0.001:
		return ""
	var along: Vector3 = direction.normalized()
	var best: String = ""
	var best_miss: float = radius
	for id: String in points:
		var to_point: Vector3 = points[id] - origin
		var ahead: float = to_point.dot(along)
		var miss: float = (to_point - along * ahead).length()
		if ahead > 0.0 and miss <= best_miss:
			best = id
			best_miss = miss
	return best


## The lines on the station in use (title first), or the titles while choosing.
func texts() -> Array[String]:
	if in_use != "":
		return _screens[in_use].texts()
	var titles: Array[String] = []
	for id: String in ids:
		titles.append_array(_screens[id].texts())
	return titles


## The refused press's reason on the station in use, or "".
func reason_text() -> String:
	return _reason


## The Fitting Bay view on station `id`, or null when none was drawn there.
func view(id: String) -> HubFittingView:
	return _views.get(id, null) as HubFittingView


## The tech tree view on station `id`, or null when none was drawn there.
func tree_view(id: String) -> HubTreeView:
	return _views.get(id, null) as HubTreeView


## Only a slot the aim newly reaches is selected, so a still hand does not
## undo a stick step.
func _point_in_station(origin: Vector3, direction: Vector3) -> String:
	var drawn: Node3D = _views.get(in_use, null)
	var at: Variant = null
	if drawn != null and drawn.call("can_point") and hub.has_method("point_slot"):
		at = drawn.call("point_on", origin, direction, _room)
	var slot: String = hub.call("slot_at", at) if at != null else ""
	if slot != _pointed_slot and slot != "":
		hub.call("point_slot", at)
		_refresh()
	_pointed_slot = slot
	return slot


func _choose(acted: String) -> void:
	if HubPanel.PAGE_STEPS.has(acted):
		highlighted = posmod(highlighted + HubPanel.PAGE_STEPS[acted], ids.size())
	elif acted == DevMenuModel.CONFIRM:
		in_use = ids[highlighted]
		hub.call("choose_station", in_use)


func _refresh() -> void:
	for id: String in ids:
		if id != in_use:
			_screens[id].show_title(_labels[id], in_use == "" and id == highlighted_id())
			if _views.has(id):
				_views[id].visible = false
			continue
		var lines: Array[String] = []
		lines.assign(hub.call("lines"))
		var first: int = hub.call("first_shown")
		var rows: Array[String] = lines.slice(1 + first, 1 + first + int(hub.call("rows_shown")))
		var chosen: int = int(hub.call("selected_line")) - 1 - first
		var drawing: Dictionary = hub.call("drawing") if hub.has_method("drawing") else {}
		_screens[id].text_floor_m = float(drawing.get("text_floor_m", -INF))
		_screens[id].show_rows(_labels[id], rows, chosen, str(hub.call("note")), _reason)
		_draw(id, first, drawing)


## Draws `drawing` (the hub text's) on station `id`, or hides what was drawn.
## A station draws one kind of thing, so its view is made once.
func _draw(id: String, first: int, drawing: Dictionary) -> void:
	if drawing.is_empty():
		if _views.has(id):
			_views[id].visible = false
		return
	if not _views.has(id):
		_views[id] = HubTreeView.new(_icons, _screen_look, HubRoom.LAYER_BIT) if drawing.get("kind", "") == "tree" \
			else HubFittingView.new(_icons, _screen_look, HubRoom.LAYER_BIT)
		_screens[id].add_child(_views[id])
	_views[id].call("show_drawing", drawing, _screens[id].shown_rows(), first, _screens[id].face_size())
