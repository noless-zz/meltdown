class_name MeltdownCue
extends Node3D

## The meltdown's cues in the cockpit (#617, RUN-2, RUN-5, MAP-2, CMF-8): a
## large countdown with the line "Escape through the entrance", and an arrow
## toward the next waypoint of the known route out.
##
## When the reactor dies, the large countdown and the line show for
## `first_show_seconds`, then hide; they show again at and below
## `warning_seconds` left, in the warning colour, until the run ends. The
## status panel's small countdown row stays on throughout; this one is for
## the moment the meltdown starts and its last stretch.
##
## The node hangs under the rig at the cockpit's eye point, so it is fixed to
## the cockpit: the head turns inside it and nothing here moves the camera
## (CMF-8). The arrow only turns. It points at the route's next corner, an
## opening between two boxes, never straight through a wall at the exit.
##
## A view: it is handed seconds, a time since the reactor died and a point,
## and reads nothing of the simulation itself (MP-2). Its look and timing come
## from `res://view/escape_cue_look.json` (ARC-4).

const NODE_NAME: String = "MeltdownCue"
const COUNTDOWN_NAME: String = "Countdown"
const LINE_NAME: String = "Line"
const ARROW_NAME: String = "Arrow"
## One step above the status panel's labels (`StatusPanel.RENDER_PRIORITY_TOP`,
## which `view/` may not name), so the panel never covers a cue.
const RENDER_PRIORITY: int = 12
## The cone's base radius and the shaft's radius, as parts of its length.
const HEAD_WIDTH: float = 0.3
const SHAFT_WIDTH: float = 0.08
## How much of the arrow's length is the cone; the rest is shaft.
const HEAD_LENGTH: float = 0.45

var countdown: Label3D
var line: Label3D
## Turns toward the waypoint; its -Z is the direction it points.
var arrow: Node3D

var _look: Dictionary


func _init(look: Dictionary = EscapeCueLook.shared()) -> void:
	name = NODE_NAME
	_look = look
	countdown = _label(COUNTDOWN_NAME, look["countdown_position_m"], int(look["countdown_font_size"]))
	line = _label(LINE_NAME, look["line_position_m"], int(look["line_font_size"]))
	line.text = look["line_text"]
	arrow = Node3D.new()
	arrow.name = ARROW_NAME
	arrow.position = look["arrow_position_m"]
	_build_arrow(float(look["arrow_length_m"]), look["arrow_color"])
	add_child(arrow)
	show_countdown(-1.0, 0.0)
	point_at(false, Vector3.ZERO, Transform3D.IDENTITY)


## Whether the large countdown shows, `elapsed_s` seconds after the reactor
## died with `seconds_left` of the meltdown left: during the first show, and
## again at and below the warning threshold.
static func large_visible(elapsed_s: float, seconds_left: float, look: Dictionary) -> bool:
	if seconds_left < 0.0:
		return false
	return elapsed_s < float(look["first_show_seconds"]) \
		or seconds_left <= float(look["warning_seconds"])


## The point the arrow aims at on `route`, corners in metres from the ship to
## the exit: the first corner after the ship. False with no point while the
## route has fewer than two corners (no route known).
static func waypoint(route: PackedVector3Array) -> Array:
	if route.size() < 2:
		return [false, Vector3.ZERO]
	return [true, route[1]]


## Shows the large countdown and its line for `seconds_left` (negative hides
## them: no meltdown), `elapsed_s` seconds after the reactor died. The text
## is rebuilt only when the shown second changes.
func show_countdown(seconds_left: float, elapsed_s: float) -> void:
	var shown: bool = large_visible(elapsed_s, seconds_left, _look)
	countdown.visible = shown
	line.visible = shown
	if not shown:
		return
	var whole: int = floori(seconds_left)
	var text: String = "%d:%02d" % [floori(whole / 60.0), whole % 60]
	# Label3D rebuilds its glyphs on every assignment; most frames change nothing.
	if countdown.text != text:
		countdown.text = text
	var warning: bool = seconds_left <= float(_look["warning_seconds"])
	countdown.modulate = _look["warning_color"] if warning else _look["text_color"]


## Shows the arrow aimed at `target`, a point in the world, when `has_target`,
## else hides it. `world_from_cue` places this node in the world: the rig's
## pose times the cockpit's eye point.
func point_at(has_target: bool, target: Vector3, world_from_cue: Transform3D) -> void:
	arrow.visible = has_target
	if not has_target:
		return
	var direction: Vector3 = world_from_cue.affine_inverse() * target - arrow.position
	if direction.length_squared() < 1e-8:
		return
	direction = direction.normalized()
	# `looking_at` needs an up that is not along the direction.
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	arrow.basis = Basis.looking_at(direction, up)


## The arrow's direction in the world, a unit vector; tests read it.
func arrow_direction(world_from_cue: Transform3D) -> Vector3:
	return (world_from_cue.basis * arrow.basis * Vector3.FORWARD).normalized()


func _label(label_name: String, at: Vector3, font_size: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.position = at
	label.pixel_size = float(_look["pixel_size"])
	label.font_size = font_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = _look["text_color"]
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = RENDER_PRIORITY
	add_child(label)
	return label


## A cone on a short shaft, tip along the arrow node's -Z, centred on it.
func _build_arrow(length: float, color: Color) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = RENDER_PRIORITY
	var head_length: float = length * HEAD_LENGTH
	var head: CylinderMesh = CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = length * HEAD_WIDTH
	head.height = head_length
	head.radial_segments = 12
	head.rings = 1
	var shaft: CylinderMesh = CylinderMesh.new()
	shaft.top_radius = length * SHAFT_WIDTH
	shaft.bottom_radius = length * SHAFT_WIDTH
	shaft.height = length - head_length
	shaft.radial_segments = 8
	shaft.rings = 1
	# The cylinders stand along +Y; a quarter turn about X lays +Y along -Z.
	var lay: Basis = Basis(Vector3.RIGHT, -PI / 2.0)
	# The tip is at -length / 2 and the tail at +length / 2.
	arrow.add_child(_part(head, material, Transform3D(lay, Vector3(0.0, 0.0, (head_length - length) / 2.0))))
	arrow.add_child(_part(shaft, material, Transform3D(lay, Vector3(0.0, 0.0, head_length / 2.0))))


static func _part(mesh: Mesh, material: Material, at: Transform3D) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.transform = at
	return part
