class_name AcceptanceStepLabel
extends Node3D

## The small label an acceptance run shows in the cockpit (#1438, DEV-6): the
## suite, the step's number and count, and the step's name, so a recording of
## the headset picture says which step is on screen. Only an acceptance run
## adds one (`AcceptanceStepLabelWiring`).
##
## It hangs under the rig and is put at the cockpit's eye point each frame, as
## the status panel is, so it stays fixed in the cockpit and the head turns
## past it; it never follows the head (CMF-8). Presentation only: it is handed
## text and a place and writes nothing else (ARC-3).
##
## The look is data, `res://xr/acceptance_step_label.json` (ARC-4):
##
##     {"position_m": [x, y, z], "pixel_size": p, "font_size": n,
##      "outline_size": n, "color": [r, g, b]}
##
## `position_m` is in the cockpit's space from the eye point (x right, y up,
## -z ahead). The default is low and centred, below the status panel and the
## middle of the view the screenshot checks judge.

const DEFAULT_FILE: String = "res://xr/acceptance_step_label.json"
## Inside the ship's 1 m collision sphere, like the status panel, so no wall comes between.
const MAX_DISTANCE_M: float = 0.9
const FALLBACK: Dictionary = {
	"position_m": Vector3(0.0, -0.3, -0.5),
	"pixel_size": 0.0003,
	"font_size": 48,
	"outline_size": 12,
	"color": Color(1.0, 0.85, 0.3),
}

## The values in use; `error` says why the file was not used, or "".
var look: Dictionary = FALLBACK.duplicate()
var error: String = ""
var label: Label3D = Label3D.new()


## What the label says: `m6  3/9  wall_depth`. A count of 0 leaves it out;
## no step yet shows the suite alone.
static func text_for(suite_name: String, number: int, count: int, step_id: String) -> String:
	if step_id == "":
		return suite_name
	var place: String = "%d/%d" % [number, count] if count > 0 else str(number)
	return "%s  %s  %s" % [suite_name, place, step_id]


## Reads `path`; returns [look, error]. A rejected file names its field and
## leaves the fallback look, so the label still shows.
static func read_look(path: String = DEFAULT_FILE) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return [FALLBACK.duplicate(), "%s: not a JSON object" % path]
	var data: Dictionary = parsed
	var read: Dictionary = {}
	for key: String in FALLBACK:
		if not data.has(key):
			return [FALLBACK.duplicate(), "%s.%s: missing" % [path, key]]
	for key: String in data:
		if not FALLBACK.has(key):
			return [FALLBACK.duplicate(), "%s.%s: not a known key" % [path, key]]
	var position: Variant = _vector(data["position_m"])
	if position == null or (position as Vector3).length() > MAX_DISTANCE_M or (position as Vector3).z >= 0.0:
		return [FALLBACK.duplicate(), "%s.position_m: three numbers ahead of the eye, within %.1f m" % [path, MAX_DISTANCE_M]]
	read["position_m"] = position
	var colour: Variant = _vector(data["color"])
	if colour == null:
		return [FALLBACK.duplicate(), "%s.color: three numbers from 0 to 1" % path]
	var rgb: Vector3 = colour
	if rgb.x < 0.0 or rgb.y < 0.0 or rgb.z < 0.0 or rgb.x > 1.0 or rgb.y > 1.0 or rgb.z > 1.0:
		return [FALLBACK.duplicate(), "%s.color: three numbers from 0 to 1" % path]
	read["color"] = Color(rgb.x, rgb.y, rgb.z)
	var ranges: Dictionary = {"pixel_size": Vector2(0.00005, 0.005), "font_size": Vector2(8, 256), "outline_size": Vector2(0, 64)}
	for key: String in ranges:
		var value: Variant = data[key]
		var bounds: Vector2 = ranges[key]
		if not (value is float or value is int) or float(value) < bounds.x or float(value) > bounds.y:
			return [FALLBACK.duplicate(), "%s.%s: a number from %s to %s" % [path, key, bounds.x, bounds.y]]
		read[key] = int(value) if key != "pixel_size" else float(value)
	return [read, ""]


static func _vector(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() != 3:
		return null
	for part: Variant in value:
		if not (part is float or part is int):
			return null
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _init(path: String = DEFAULT_FILE) -> void:
	name = "AcceptanceStepLabel"
	var got: Array = read_look(path)
	look = got[0]
	error = got[1]
	label.name = "Text"
	label.pixel_size = look["pixel_size"]
	label.font_size = look["font_size"]
	label.outline_size = look["outline_size"]
	label.modulate = look["color"]
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	# Drawn over the dash, which would otherwise hide it from the eye.
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.shaded = false
	add_child(label)


func show_text(text: String) -> void:
	label.text = text
	visible = text != ""


## Puts the label at `cockpit`, the eye point in the rig's space, facing the eye.
func place(cockpit: Transform3D) -> void:
	transform = cockpit * offset()


## The label's place in the cockpit's space: `position_m`, turned to face the eye point.
func offset() -> Transform3D:
	var at: Vector3 = look["position_m"]
	# Label3D reads from +z, so -z points away from the eye.
	return Transform3D(Basis.looking_at(at, Vector3.UP), at)
