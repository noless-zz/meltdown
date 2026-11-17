class_name DebrisView
extends Node3D

## Draws meltdown debris (RUN-4): one sphere node per entry, in one of three
## looks. A solid entry is an opaque, rock-coloured faceted sphere. An entry
## that has not fallen yet is hidden until `warn_seconds` before it falls,
## then shows as a see-through orange glow at its place, so the player sees
## the danger before it lands. A held entry (skipped because it would have
## sealed the last route, #397) is a coarser, see-through shell: a cave-in
## that cracked but did not come down, which must not look like a wall.
##
## It takes plain values, never a `Sim` or session, and writes nothing back
## (MP-2). Debris glows faintly by itself because the mine is dark (LGT-1);
## it adds no lights, so the 8-light budget is untouched (GFX-4). The glow is
## steady: nothing flashes. The look lives in `res://view/debris_look.json`
## (`DebrisLook`, ARC-4).
##
## A box entry (a blast door or a collapsed ceiling, #459) is an axis-aligned
## slab of its size with its own `slab_*` look, going through the same hidden,
## warning and solid stages. A held box is not drawn at all: a see-through
## slab across an opening would read as a door, and the route there is open.

const NODE_NAME: String = "DebrisView"
const ENTRY_PREFIX: String = "Debris"

enum EntryState { HIDDEN, WARNING, SOLID, HELD }

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Times a mesh was built, for tests: meshes are built once, never per call.
var mesh_builds: int = 0

var _look: Dictionary = DebrisLook.FALLBACK
var _rock_mesh: SphereMesh
var _cracked_mesh: SphereMesh
var _solid_material: StandardMaterial3D
var _warn_material: StandardMaterial3D
var _held_material: StandardMaterial3D
var _slab_mesh: BoxMesh
var _slab_material: StandardMaterial3D
var _slab_warn_material: StandardMaterial3D
var _entries: Array[MeshInstance3D] = []
var _states: Array[EntryState] = []
var _boxes: Array[bool] = []


func _init() -> void:
	name = NODE_NAME
	_solid_material = _new_material(false)
	_warn_material = _new_material(true)
	_held_material = _new_material(true)
	_slab_material = _new_material(false)
	_slab_warn_material = _new_material(true)
	# More facets read as a whole rock; fewer, as a broken one.
	_rock_mesh = _build_mesh(10, 5)
	_cracked_mesh = _build_mesh(5, 3)
	_slab_mesh = BoxMesh.new()
	_slab_mesh.size = Vector3.ONE
	mesh_builds += 1
	load_look()


## Applies the look file at `path`. A missing or rejected file keeps the
## built-in look, sets `look_error` and pushes a warning naming the key.
## Returns `look_error`.
func load_look(path: String = DebrisLook.DEFAULT_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = DebrisLook.parse(FileAccess.get_file_as_string(path))
	else:
		values = {"error": "file not found"}
	_look = DebrisLook.FALLBACK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("DebrisView uses the built-in look; %s" % look_error)
	else:
		_look = values
	_paint(_solid_material, _look["solid_color"], float(_look["solid_energy"]), 1.0)
	_paint(_warn_material, _look["warn_color"], float(_look["warn_energy"]), float(_look["warn_alpha"]))
	_paint(_held_material, _look["held_color"], float(_look["held_energy"]), float(_look["held_alpha"]))
	_paint(_slab_material, _look["slab_color"], float(_look["slab_energy"]), 1.0)
	_paint(_slab_warn_material, _look["slab_warn_color"], float(_look["slab_warn_energy"]),
		float(_look["slab_warn_alpha"]))
	return look_error


## The look in use.
func look() -> Dictionary:
	return _look


## Shows every debris entry. The arrays run in parallel; extra values in a
## longer array are ignored. Existing nodes are reused, so this is cheap to
## call every frame, and nodes past the last entry are freed. An entry with
## a radius of zero or less is hidden. `sizes_m` (the snapshot's `sizes_m` key)
## gives a box entry's full size and zero for a sphere; a missing or shorter
## array makes the remaining entries spheres, as before boxes.
func show_debris(positions_m: Array[Vector3], radii_m: Array[float], solid: Array[bool], held: Array[bool], seconds_to_fall: Array[float], sizes_m: Array[Vector3] = []) -> void:
	var count: int = mini(mini(positions_m.size(), radii_m.size()), mini(mini(solid.size(), held.size()), seconds_to_fall.size()))
	while _entries.size() > count:
		var extra: MeshInstance3D = _entries.pop_back()
		_states.pop_back()
		_boxes.pop_back()
		remove_child(extra)
		extra.free()
	while _entries.size() < count:
		var entry: MeshInstance3D = MeshInstance3D.new()
		entry.name = "%s%d" % [ENTRY_PREFIX, _entries.size()]
		entry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(entry)
		_entries.append(entry)
		_states.append(EntryState.HIDDEN)
		_boxes.append(false)
	for index: int in count:
		var size_m: Vector3 = sizes_m[index] if index < sizes_m.size() else Vector3.ZERO
		var is_box: bool = size_m != Vector3.ZERO
		var state: EntryState = box_state_for(size_m, solid[index], held[index], seconds_to_fall[index]) \
			if is_box else state_for(radii_m[index], solid[index], held[index], seconds_to_fall[index])
		var entry: MeshInstance3D = _entries[index]
		_states[index] = state
		_boxes[index] = is_box
		entry.visible = state != EntryState.HIDDEN
		entry.position = positions_m[index]
		if is_box:
			entry.scale = size_m.max(Vector3.ONE * 0.001)
			entry.mesh = _slab_mesh
			entry.material_override = slab_material_for(state)
		else:
			entry.scale = Vector3.ONE * maxf(radii_m[index], 0.001)
			entry.mesh = _cracked_mesh if state == EntryState.HELD else _rock_mesh
			entry.material_override = material_for(state)


## Which look an entry gets. Held wins over solid: a held entry never fell.
## An entry still to fall is shown only within `warn_seconds` of falling.
func state_for(radius_m: float, solid: bool, held: bool, seconds_to_fall: float) -> EntryState:
	if radius_m <= 0.0:
		return EntryState.HIDDEN
	if held:
		return EntryState.HELD
	return _falling_state(solid, seconds_to_fall)


## Which look a box entry gets: the sphere stages, except that a held box, or
## one with a side of zero or less, is hidden.
func box_state_for(size_m: Vector3, solid: bool, held: bool, seconds_to_fall: float) -> EntryState:
	if held or minf(size_m.x, minf(size_m.y, size_m.z)) <= 0.0:
		return EntryState.HIDDEN
	return _falling_state(solid, seconds_to_fall)


func _falling_state(solid: bool, seconds_to_fall: float) -> EntryState:
	if solid:
		return EntryState.SOLID
	if seconds_to_fall <= float(_look["warn_seconds"]):
		return EntryState.WARNING
	return EntryState.HIDDEN


## The material for a state; null for `HIDDEN`.
func material_for(state: EntryState) -> StandardMaterial3D:
	match state:
		EntryState.SOLID:
			return _solid_material
		EntryState.WARNING:
			return _warn_material
		EntryState.HELD:
			return _held_material
	return null


## The material for a box entry's state; null for `HIDDEN` and `HELD`.
func slab_material_for(state: EntryState) -> StandardMaterial3D:
	match state:
		EntryState.SOLID:
			return _slab_material
		EntryState.WARNING:
			return _slab_warn_material
	return null


func entry_count() -> int:
	return _entries.size()


func entry(index: int) -> MeshInstance3D:
	return _entries[index]


func entry_state(index: int) -> EntryState:
	return _states[index]


func entry_is_box(index: int) -> bool:
	return _boxes[index]


## Radius of the drawn sphere of entry `index`, metres; zero for a box.
func entry_radius(index: int) -> float:
	if _boxes[index]:
		return 0.0
	var sphere: SphereMesh = _entries[index].mesh
	return sphere.radius * _entries[index].scale.x


## Full size of the drawn slab of entry `index`, metres; zero for a sphere.
func entry_size(index: int) -> Vector3:
	if not _boxes[index]:
		return Vector3.ZERO
	var slab: BoxMesh = _entries[index].mesh
	return slab.size * _entries[index].scale


func _new_material(see_through: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.roughness = 1.0
	if see_through:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Both faces, so the glow still shows with the ship inside it.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _paint(material: StandardMaterial3D, color: Color, energy: float, alpha: float) -> void:
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission = color
	material.emission_energy_multiplier = energy


## A unit sphere; each node's scale is its entry's radius, so a new radius
## never needs a new mesh.
func _build_mesh(segments: int, rings: int) -> SphereMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
	mesh_builds += 1
	return sphere
