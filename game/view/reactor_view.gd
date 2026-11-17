class_name ReactorView
extends Node3D

## Draws the reactor (RUN-2): a glowing sphere of the reactor's radius with
## one omni light, so it reads as the target from across its dark room
## (LGT-1). Intact, it pulses slowly, and faster as its hull drops. Destroyed,
## the core dims to a wreck colour and the light flickers in the meltdown
## colour, faster as the countdown runs down, fastest under
## `FASTEST_UNDER_SECONDS`.
##
## It takes plain values, never a `Sim` or session, and writes nothing back
## (MP-2). The pulse runs on the view's own clock. Only light and emission
## change; nothing moves, so the meltdown never moves the view (CMF-3).
##
## The light counts toward the 8-light budget (GFX-4) and casts no shadow:
## only the player's headlight does. The look lives in
## `res://view/reactor_look.json` (`ReactorLook`, ARC-4).

const NODE_NAME: String = "ReactorView"
const CORE_NAME: String = "Core"
const LIGHT_NAME: String = "Light"
## Same threshold as the status panel's red meltdown row (#315), so the
## reactor and the panel both turn urgent at once. Kept here because view
## code may not read `xr/`.
const FASTEST_UNDER_SECONDS: float = 30.0

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""
## Times the core mesh was built, for tests: it is built once, never per frame.
var mesh_builds: int = 0
## Where in the current pulse the view is, 0..1. View state only.
var pulse_phase: float = 0.0

var _look: Dictionary = ReactorLook.FALLBACK
var _core: MeshInstance3D
var _light: OmniLight3D
var _material: StandardMaterial3D
var _radius: float = 1.0
var _hull_fraction: float = 1.0
var _destroyed: bool = false
var _seconds_left: float = 0.0


func _init() -> void:
	name = NODE_NAME
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_core = MeshInstance3D.new()
	_core.name = CORE_NAME
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.mesh = _build_mesh()
	add_child(_core)
	_light = OmniLight3D.new()
	_light.name = LIGHT_NAME
	_light.shadow_enabled = false
	add_child(_light)
	visible = false
	load_look()


func _process(delta: float) -> void:
	advance(delta)


## Applies the look file at `path`. A missing or rejected file keeps the
## built-in look, sets `look_error` and pushes a warning naming the field.
## Returns `look_error`.
func load_look(path: String = ReactorLook.DEFAULT_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = ReactorLook.parse(FileAccess.get_file_as_string(path))
	else:
		values = {"error": "file not found"}
	_look = ReactorLook.FALLBACK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("ReactorView uses the built-in look; %s" % look_error)
	else:
		_look = values
	_light.omni_range = float(_look["light_range"])
	_apply()
	return look_error


## The look in use.
func look() -> Dictionary:
	return _look


## Places and sets up the reactor. Cheap to call every frame: it moves and
## scales the existing nodes and never rebuilds the mesh. A radius of zero or
## less hides the reactor.
func show_state(position_m: Vector3, radius: float, hull_fraction: float, destroyed: bool, meltdown_seconds_left: float) -> void:
	position = position_m
	visible = radius > 0.0
	_radius = maxf(radius, 0.0)
	_hull_fraction = clampf(hull_fraction, 0.0, 1.0)
	_destroyed = destroyed
	_seconds_left = maxf(meltdown_seconds_left, 0.0)
	_core.scale = Vector3.ONE * maxf(_radius, 0.001)
	_apply()


## Seconds per pulse (intact) or flicker (destroyed) for the current state.
func pulse_period() -> float:
	if not _destroyed:
		return lerpf(float(_look["pulse_period_no_hull"]), float(_look["pulse_period_full_hull"]), _hull_fraction)
	var fast: float = float(_look["flicker_period_fast"])
	if _seconds_left <= FASTEST_UNDER_SECONDS:
		return fast
	var ramp: float = (_seconds_left - FASTEST_UNDER_SECONDS) / float(_look["flicker_ramp_seconds"])
	return lerpf(fast, float(_look["flicker_period_slow"]), clampf(ramp, 0.0, 1.0))


## Moves the pulse on by `seconds` of view time. The phase advances by
## fractions of the current period, so a change of rate never jumps the
## brightness.
func advance(seconds: float) -> void:
	pulse_phase = fposmod(pulse_phase + maxf(seconds, 0.0) / pulse_period(), 1.0)
	_apply()


## Brightness of the pulse now, from `1 - pulse_depth` to 1.
func pulse_level() -> float:
	var wave: float = 0.5 + 0.5 * cos(TAU * pulse_phase)
	return 1.0 - float(_look["pulse_depth"]) * (1.0 - wave)


## Radius of the drawn sphere, metres.
func core_radius() -> float:
	var sphere: SphereMesh = _core.mesh
	return sphere.radius * _core.scale.x


func core() -> MeshInstance3D:
	return _core


func light() -> OmniLight3D:
	return _light


func material() -> StandardMaterial3D:
	return _material


func _apply() -> void:
	var level: float = pulse_level()
	var core_color: Color = _look["wreck_color"] if _destroyed else _look["core_color"]
	var core_energy: float = float(_look["wreck_energy"] if _destroyed else _look["core_energy"])
	_material.albedo_color = core_color
	_material.emission = core_color
	_material.emission_energy_multiplier = core_energy * level
	_light.light_color = _look["meltdown_light_color"] if _destroyed else _look["light_color"]
	_light.light_energy = float(_look["light_energy"]) * level


## A unit sphere; the node's scale is the reactor's radius, so a new radius
## never needs a new mesh.
func _build_mesh() -> SphereMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = _material
	mesh_builds += 1
	return sphere
