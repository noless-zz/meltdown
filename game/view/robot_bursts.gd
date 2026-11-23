class_name RobotBursts
extends Node3D

## The destruction bursts of `RobotView` (#604, CMB-3), where a robot left the
## array, over `burst_seconds`. Since #1309 a blast has depth: a hot core that
## shrinks fast, a shell in the burst colour that swells to `burst_radii` of
## the robot's radius, bright at its rim and see-through in its middle
## (`blast_glow.gdshader`, added onto the scene so robots behind still show),
## and a burst of sparks. Both balls fade out quickly.
##
## At point-blank range a blast must not blank the view (the owner's playtest
## of 23 Nov): the balls are kept `NEAR_M` short of the viewer set with
## `set_viewer`, and fade as the viewer gets that close. Pooled like the robots.

const NODE_NAME: String = "Bursts"
const SHADER: Shader = preload("res://view/blast_glow.gdshader")
## The balls' surface stays at least this far from the viewer, metres.
const NEAR_M: float = 0.75
## Over this distance beyond `NEAR_M` a blast fades in, so one at the pilot's
## nose is faint rather than a wall of colour.
const NEAR_FADE_M: float = 2.0
## The core's radius at the start, as a share of the robot's, and the share
## of `burst_seconds` it lasts.
const CORE_RADII: float = 1.2
const CORE_SHARE: float = 0.35
## The core is the burst colour this far towards white.
const CORE_WHITEN: float = 0.6
const SPARK_COUNT: int = 18
## Sparks fly this many robot radii per second at their fastest.
const SPARK_RADII_PER_S: float = 9.0

var _shells: Array[MeshInstance3D] = []
var _cores: Array[MeshInstance3D] = []
var _mesh: PrimitiveMesh = RobotView.build_mesh("sphere")
var _sparks: BoltSparks = BoltSparks.new("BlastSparks")
## The bursts that already threw their sparks, by `_key`.
var _sparked: Dictionary[String, bool] = {}
var _viewer: Vector3 = Vector3.ZERO
var _has_viewer: bool = false
var _count: int = 0


func _init() -> void:
	name = NODE_NAME
	add_child(_sparks)


## Where the camera is, in this node's space; blasts keep clear of it.
func set_viewer(at: Vector3) -> void:
	_viewer = at
	_has_viewer = true


## Draws `bursts` (`RobotHitTracker.bursts`) at time `now` with `effects`.
func show_bursts(bursts: Array[Dictionary], effects: Dictionary, now: float) -> void:
	var seconds: float = effects["burst_seconds"]
	var color: Color = effects["burst_color"]
	while _shells.size() < bursts.size():
		_add_node()
	var keys: Dictionary[String, bool] = {}
	_count = bursts.size()
	for index: int in _shells.size():
		var shell: MeshInstance3D = _shells[index]
		var core: MeshInstance3D = _cores[index]
		shell.visible = index < bursts.size()
		core.visible = shell.visible
		if not shell.visible:
			continue
		var burst: Dictionary = bursts[index]
		var at: Vector3 = burst["position"]
		var radius: float = burst["radius"]
		var key: String = _key(burst)
		keys[key] = true
		if not _sparked.has(key):
			_sparks.burst(at, Vector3.UP, SPARK_COUNT, radius * SPARK_RADII_PER_S, seconds,
				color.lerp(Color.WHITE, CORE_WHITEN * 0.5), true)
		var t: float = clampf((now - float(burst["start"])) / seconds, 0.0, 1.0)
		var room: float = INF if not _has_viewer else maxf(0.0, at.distance_to(_viewer) - NEAR_M)
		var near_fade: float = 1.0 if not _has_viewer else clampf(room / NEAR_FADE_M, 0.0, 1.0)
		# Fast at first and slowing, as a blast does.
		var grow: float = lerpf(0.5, float(effects["burst_radii"]), 1.0 - pow(1.0 - t, 3.0))
		_paint(shell, at, minf(radius * grow, room), color, pow(1.0 - t, 2.0) * near_fade, 0.8)
		var core_t: float = clampf(t / CORE_SHARE, 0.0, 1.0)
		_paint(core, at, minf(radius * CORE_RADII * (1.0 - core_t), room),
			color.lerp(Color.WHITE, CORE_WHITEN), (1.0 - core_t) * near_fade, 0.2)
	_sparked = keys


## Bursts drawn by the last `show_bursts`.
func visible_count() -> int:
	return _count


## The shell and core of pooled burst `index`, for tests.
func shell(index: int) -> MeshInstance3D:
	return _shells[index]


func core(index: int) -> MeshInstance3D:
	return _cores[index]


## The spark bursts thrown by blasts.
func sparks() -> BoltSparks:
	return _sparks


static func _key(burst: Dictionary) -> String:
	return "%s|%s" % [burst["start"], burst["position"]]


static func _paint(node: MeshInstance3D, at: Vector3, radius: float, color: Color, strength: float,
		hollow: float) -> void:
	node.visible = radius > 0.01 and strength > 0.0
	if not node.visible:
		return
	node.transform = Transform3D(Basis.from_scale(Vector3.ONE * radius), at)
	var material: ShaderMaterial = node.material_override as ShaderMaterial
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("hollow", hollow)


func _add_node() -> void:
	for pool: Array[MeshInstance3D] in [_shells, _cores]:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = _mesh
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SHADER
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		pool.append(instance)
