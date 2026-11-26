extends RefCounted

## The `ambient_tints_baked` check (#1400, GFX-5, GFX-4, PRF-4, DEV-6), lane-b's
## file under `acceptance/checks/`. In `suites/m6/effects.json` the `wall_depth`
## and `portal_visibility` steps fly G2 with screenshots; this check reads the
## level view in the main scene: the look's ambient rules were applied, the
## boxes bake at least two different ambients, every wall and bevel vertex
## carries its baked light in a material that uses it, no box draws more than
## its two surfaces and the view adds no light. It reads the view only; the
## steps' pinned hashes hold the simulation (ARC-1). Whether rooms differ in
## mood without looking patchy stays human-checked in the headset.

const CHECK: String = "ambient_tints_baked"
## Two ambients closer than this on every channel count as one tint.
const SAME_TINT: float = 0.002


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	var view: LevelView = main.get_node_or_null(LevelView.NODE_NAME) as LevelView if main != null else null
	return judge_view(view, measurements)


## [result, message] for `view`, adding the tints it baked to `measurements`.
static func judge_view(view: LevelView, measurements: Dictionary) -> Array:
	if view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no level"]
	if view.ambient_error != "":
		return [AcceptanceReport.RESULT_FAIL, "the ambient rules were rejected: %s" % view.ambient_error]
	var bake: AmbientBake = view.ambient_bake()
	if bake == null:
		return [AcceptanceReport.RESULT_FAIL, "the level was built without an ambient bake"]
	var tints: Array[Color] = distinct(bake.ambients)
	measurements["ambient_tints"] = tints.size()
	if tints.size() < 2:
		return [AcceptanceReport.RESULT_FAIL, "every box bakes the same ambient %s" % tints]
	for box: int in view.box_count():
		if view.surfaces_of(box) > 2:
			return [AcceptanceReport.RESULT_FAIL, "box %d costs %d draw calls" % [box, view.surfaces_of(box)]]
		for part: MeshInstance3D in [view.walls_of(box), view.bevels_of(box)]:
			var problem: String = _baked_part(part)
			if problem != "":
				return [AcceptanceReport.RESULT_FAIL, "box %d: %s" % [box, problem]]
	var lights: int = _lights(view)
	if lights > 0:
		return [AcceptanceReport.RESULT_FAIL, "the level view holds %d lights" % lights]
	return [AcceptanceReport.RESULT_PASS, "%d boxes bake %d ambient tints in %d wall pieces" \
			% [view.box_count(), tints.size(), view.wall_pieces()]]


## `colors` without near repeats, in first-seen order.
static func distinct(colors: Array[Color]) -> Array[Color]:
	var result: Array[Color] = []
	for color: Color in colors:
		var seen: bool = false
		for kept: Color in result:
			seen = seen or (absf(kept.r - color.r) < SAME_TINT and absf(kept.g - color.g) < SAME_TINT \
					and absf(kept.b - color.b) < SAME_TINT)
		if not seen:
			result.append(color)
	return result


static func _baked_part(part: MeshInstance3D) -> String:
	if part == null or part.mesh == null:
		return ""
	for surface: int in part.mesh.get_surface_count():
		var vertices: int = (part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if LevelViewMeshes.baked(part.mesh, surface).size() != vertices * 3:
			return "%s has %d vertices without their baked ambient" % [part.name, vertices]
		var material: ShaderMaterial = part.mesh.surface_get_material(surface) as ShaderMaterial
		if material == null or material.get_shader_parameter("baked_ambient") != true:
			return "%s does not draw with its baked ambient" % part.name
	return ""


static func _lights(node: Node) -> int:
	var count: int = 1 if node is Light3D else 0
	for child: Node in node.get_children():
		count += _lights(child)
	return count
