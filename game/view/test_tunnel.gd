class_name TestTunnel
extends Node3D

## A straight 30 m tunnel built from primitive meshes, used to judge stereo
## depth, scale and head tracking in the headset (gate G0). It is built in
## code so the scene file stays tiny and reviewable.
##
## The player stands at the origin looking down negative z. Reference
## markers sit at known distances so depth errors are easy to spot.
##
## Walls, fog and ambient light come from the same look file as every other
## level (`LevelLook`, #609), so the tunnel reads like the mines do.

const LENGTH: float = 30.0
const WIDTH: float = 4.0
const HEIGHT: float = 4.0
const WALL: float = 0.2
const START_Z: float = 2.0
const STRIPE_SPACING: float = 5.0
const MARKER_DISTANCES: Array[float] = [1.0, 5.0, 20.0]
# Sideways offsets chosen so that no marker hides another at any eye height:
# the 5 m and 20 m markers are about 11 degrees apart, and the wide 20 m label
# stays clear of both walls on the centre line.
const MARKER_OFFSETS_X: Array[float] = [-0.5, 1.0, 0.0]
# Markers nearer than this hang their label below the ball. Above it, the 1 m
# label sat about 34 degrees up from the start eye, outside the preset 1 and 2
# windows (#249); farther labels stay above, where they already fit.
const LABEL_BELOW_UNDER_M: float = 2.0
const LIGHT_POSITIONS_Z: Array[float] = [-3.0, -12.0, -22.0]
const LIGHT_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.3),
	Color(0.3, 1.0, 0.6),
	Color(0.35, 0.5, 1.0),
]

var _built: bool = false
var _look: Dictionary = {}


## The open space inside the walls, floor and ceiling, as the box ships fly in
## (FLT-3), for a tunnel node placed at `offset`. The session's walls come from
## here, so they cannot drift away from the walls drawn by `_add_shell`.
static func interior_box(offset: Vector3 = Vector3.ZERO) -> BoxBounds:
	var low: Vector3 = Vector3(-WIDTH / 2.0, 0.0, START_Z - LENGTH)
	var high: Vector3 = Vector3(WIDTH / 2.0, HEIGHT, START_Z)
	return BoxBounds.new(low + offset, high + offset)


func _ready() -> void:
	build()


## Creates the tunnel once. Public so tests can build it outside the tree.
func build() -> void:
	if _built:
		return
	_built = true
	_look = LevelLook.load_or_fallback()
	_add_environment()
	_add_shell()
	_add_lights()
	_add_markers()


func _add_environment() -> void:
	add_child(LevelLook.world_environment(_look, "Environment"))


func _add_shell() -> void:
	var shell: Node3D = Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	var center_z: float = START_Z - LENGTH / 2.0
	# Each box is tinted by the way its inner face points, as level walls are.
	var floor_look: Material = LevelLook.wall_material(_look, LevelLook.tint_for(_look, Vector3.UP))
	var ceiling_look: Material = LevelLook.wall_material(_look, LevelLook.tint_for(_look, Vector3.DOWN))
	var wall_look: Material = LevelLook.wall_material(_look, LevelLook.tint_for(_look, Vector3.RIGHT))
	var side_x: float = (WIDTH + WALL) / 2.0
	_add_shell_box(shell, "Floor", Vector3(WIDTH + 2.0 * WALL, WALL, LENGTH), Vector3(0.0, -WALL / 2.0, center_z), floor_look)
	_add_shell_box(shell, "Ceiling", Vector3(WIDTH + 2.0 * WALL, WALL, LENGTH), Vector3(0.0, HEIGHT + WALL / 2.0, center_z), ceiling_look)
	_add_shell_box(shell, "LeftWall", Vector3(WALL, HEIGHT, LENGTH), Vector3(-side_x, HEIGHT / 2.0, center_z), wall_look)
	_add_shell_box(shell, "RightWall", Vector3(WALL, HEIGHT, LENGTH), Vector3(side_x, HEIGHT / 2.0, center_z), wall_look)
	_add_shell_box(shell, "FarEnd", Vector3(WIDTH, HEIGHT, WALL), Vector3(0.0, HEIGHT / 2.0, START_Z - LENGTH - WALL / 2.0), wall_look)
	_add_shell_box(shell, "NearEnd", Vector3(WIDTH, HEIGHT, WALL), Vector3(0.0, HEIGHT / 2.0, START_Z + WALL / 2.0), wall_look)
	# Floor stripes every few metres give a steady depth cue along the tunnel.
	var stripe_color: Color = Color(0.9, 0.75, 0.1)
	var stripe_count: int = int(LENGTH / STRIPE_SPACING)
	for i: int in stripe_count:
		var z: float = -STRIPE_SPACING * float(i + 1)
		if z < START_Z - LENGTH:
			break
		_add_box(shell, "Stripe%d" % i, Vector3(WIDTH, 0.02, 0.2), Vector3(0.0, 0.01, z), stripe_color)


func _add_lights() -> void:
	var lights: Node3D = Node3D.new()
	lights.name = "Lights"
	add_child(lights)
	for i: int in LIGHT_POSITIONS_Z.size():
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "Light%d" % i
		light.light_color = LIGHT_COLORS[i]
		light.light_energy = 2.0
		light.omni_range = 9.0
		light.position = Vector3(0.0, HEIGHT - 0.5, LIGHT_POSITIONS_Z[i])
		lights.add_child(light)


func _add_markers() -> void:
	var markers: Node3D = Node3D.new()
	markers.name = "Markers"
	add_child(markers)
	for i: int in MARKER_DISTANCES.size():
		var distance: float = MARKER_DISTANCES[i]
		var marker: Node3D = Node3D.new()
		marker.name = "Marker%d" % i
		marker.position = Vector3(MARKER_OFFSETS_X[i], 1.4, -distance)
		markers.add_child(marker)

		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 1.0, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.9, 0.9, 0.9)
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 0.15
		mesh.height = 0.3
		mesh.material = material
		var ball: MeshInstance3D = MeshInstance3D.new()
		ball.name = "Ball"
		ball.mesh = mesh
		marker.add_child(ball)

		var label: Label3D = Label3D.new()
		label.name = "Label"
		label.text = "%d m" % int(distance)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.004 * maxf(1.0, distance / 2.0)
		var label_rise: float = 0.3 + 0.05 * distance
		if distance < LABEL_BELOW_UNDER_M:
			label_rise = -label_rise
		label.position = Vector3(0.0, label_rise, 0.0)
		marker.add_child(label)


func _add_box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	_add_shell_box(parent, box_name, size, at, material)


func _add_shell_box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = box_name
	box.mesh = mesh
	box.position = at
	parent.add_child(box)
