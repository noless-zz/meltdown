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
## (`DebrisLook`, ARC-4); the meshes are in `DebrisMeshes` and the materials
## in `DebrisMaterials`.
##
## A box entry (a blast door or a collapsed ceiling, #459) is an axis-aligned
## slab of its size with its own `slab_*` look, going through the same hidden,
## warning and solid stages. A held box is not drawn at all: a see-through
## slab across an opening would read as a door, and the route there is open.
##
## A fire entry (#496) is drawn in its own shape and size, see-through and
## glowing in the `fire_*` look, from its fall tick on (`BURNING`). Before that it
## shows the sphere warning look, so every coming danger warns alike; a held fire
## is not drawn. A burning fire sphere is drawn as a faceted upward cone, a
## flame, filling the sphere's height: a glowing ball there was taken for the
## reactor core (#1208). Its glow flickers with the tick it is handed, never with the
## clock, so a paused session draws the same frame (CMF-8). The view adds no
## collision and no full-screen pass (GFX-6).

const NODE_NAME: String = "DebrisView"
const ENTRY_PREFIX: String = "Debris"

enum EntryState { HIDDEN, WARNING, SOLID, HELD, BURNING }

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Times a mesh was built, for tests: meshes are built once, never per call.
var mesh_builds: int = 0

var _look: Dictionary = DebrisLook.FALLBACK
var _meshes: DebrisMeshes
var _materials: DebrisMaterials = DebrisMaterials.new()
var _entries: Array[MeshInstance3D] = []
var _states: Array[EntryState] = []
var _boxes: Array[bool] = []
var _fires: Array[bool] = []
## The tick the fire glow was last set for.
var _fire_tick: int = 0


func _init() -> void:
	name = NODE_NAME
	_meshes = DebrisMeshes.new()
	mesh_builds += _meshes.builds
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
	_materials.paint(_look, _fire_tick)
	return look_error


## The look in use.
func look() -> Dictionary:
	return _look


## Shows every debris entry. The arrays run in parallel; extra values in a
## longer array are ignored. Existing nodes are reused, so this is cheap to
## call every frame, and nodes past the last entry are freed. An entry with
## a radius of zero or less is hidden. `sizes_m` (the snapshot's `sizes_m` key)
## gives a box entry's full size and zero for a sphere; a missing or shorter
## array makes the remaining entries spheres, as before boxes. `kinds` (the
## snapshot's `kinds` key) marks fire entries; without it none is fire. `tick` is
## the simulation tick the snapshot was taken at, which drives the fire flicker.
func show_debris(positions_m: Array[Vector3], radii_m: Array[float], solid: Array[bool], held: Array[bool], seconds_to_fall: Array[float], sizes_m: Array[Vector3] = [], kinds: Array[String] = [], tick: int = 0) -> void:
	var count: int = mini(mini(positions_m.size(), radii_m.size()), mini(mini(solid.size(), held.size()), seconds_to_fall.size()))
	while _entries.size() > count:
		var extra: MeshInstance3D = _entries.pop_back()
		_states.pop_back()
		_boxes.pop_back()
		_fires.pop_back()
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
		_fires.append(false)
	for index: int in count:
		var size_m: Vector3 = sizes_m[index] if index < sizes_m.size() else Vector3.ZERO
		var is_box: bool = size_m != Vector3.ZERO
		var is_fire: bool = index < kinds.size() and kinds[index] == MeltdownFire.KIND_FIRE
		var state: EntryState = box_state_for(size_m, solid[index], held[index], seconds_to_fall[index]) \
			if is_box else state_for(radii_m[index], solid[index], held[index], seconds_to_fall[index])
		if is_fire:
			state = fire_state_for(radii_m[index], size_m, held[index], seconds_to_fall[index])
		var entry: MeshInstance3D = _entries[index]
		_states[index] = state
		_boxes[index] = is_box
		_fires[index] = is_fire
		entry.visible = state != EntryState.HIDDEN
		entry.position = positions_m[index]
		if is_box:
			entry.scale = size_m.max(Vector3.ONE * 0.001)
			entry.mesh = _meshes.slab
			entry.material_override = slab_material_for(state)
		else:
			entry.scale = Vector3.ONE * maxf(radii_m[index], 0.001)
			entry.mesh = _meshes.cracked if state == EntryState.HELD else _meshes.rock
			entry.material_override = material_for(state)
		if is_fire:
			entry.material_override = fire_material_for(state)
			if not is_box and state == EntryState.BURNING:
				entry.mesh = _meshes.flame
	if tick != _fire_tick:
		_fire_tick = tick
		_materials.flicker_fire(_look, tick)


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


## Which look a fire entry gets: hidden when held or of no size, burning from
## its fall, and the shared warning within `warn_seconds` before it.
func fire_state_for(radius_m: float, size_m: Vector3, held: bool, seconds_to_fall: float) -> EntryState:
	var empty: bool = minf(size_m.x, minf(size_m.y, size_m.z)) <= 0.0 \
		if size_m != Vector3.ZERO else radius_m <= 0.0
	if held or empty:
		return EntryState.HIDDEN
	if seconds_to_fall <= 0.0:
		return EntryState.BURNING
	return _falling_state(false, seconds_to_fall)


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
			return _materials.solid
		EntryState.WARNING:
			return _materials.warn
		EntryState.HELD:
			return _materials.held
	return null


## The material for a fire entry's state, whatever its shape: the sphere
## warning, the fire look once burning, null otherwise.
func fire_material_for(state: EntryState) -> StandardMaterial3D:
	match state:
		EntryState.WARNING:
			return _materials.warn
		EntryState.BURNING:
			return _materials.fire
	return null


## The material for a box entry's state; null for `HIDDEN` and `HELD`.
func slab_material_for(state: EntryState) -> StandardMaterial3D:
	match state:
		EntryState.SOLID:
			return _materials.slab
		EntryState.WARNING:
			return _materials.slab_warn
	return null


func entry_count() -> int:
	return _entries.size()


func entry(index: int) -> MeshInstance3D:
	return _entries[index]


func entry_state(index: int) -> EntryState:
	return _states[index]


func entry_is_box(index: int) -> bool:
	return _boxes[index]


func entry_is_fire(index: int) -> bool:
	return _fires[index]


## Radius of the drawn sphere (or a burning fire's flame) of entry `index`,
## metres; zero for a box. Every round mesh is of unit radius, scaled.
func entry_radius(index: int) -> float:
	if _boxes[index]:
		return 0.0
	return _entries[index].scale.x


## Full size of the drawn slab of entry `index`, metres; zero for a sphere.
func entry_size(index: int) -> Vector3:
	if not _boxes[index]:
		return Vector3.ZERO
	var slab: BoxMesh = _entries[index].mesh
	return slab.size * _entries[index].scale

