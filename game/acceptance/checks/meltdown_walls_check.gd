extends RefCounted

## The `meltdown_walls_shown` check (#1454, GFX-6, GFX-4, CMF-8, DEV-6,
## decision record 0005), lane-a's file under `acceptance/checks/`. In
## `suites/m6/effects.json` the `meltdown_walls` step flies the stress replay,
## whose reactor dies within its first second, and saves screenshots; at the
## end this check requires:
##
## - the look's `meltdown` section was read (`MeltdownWalls` enabled, no error);
## - the reactor is dead and the walls' look has ramped in: the emission is
##   above zero and at most `MeltdownWallRules.MAX_EMISSION`, and the strips'
##   brightness is within `MeltdownWallRules.MAX_STRIP_SWING` of full;
## - the walls' and the bevels' (guide strips') materials of every box carry
##   that same `meltdown` uniform, so what was computed is what is drawn.
##
## It reads the scene and writes nothing; the step's pinned hash holds the
## simulation (ARC-1). Whether the mine says "get out" without flashing stays
## human-checked in the headset.

const CHECK: String = "meltdown_walls_shown"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	var view: LevelView = main.get_node_or_null(LevelView.NODE_NAME) as LevelView if main != null else null
	var session: LocalSession = main.get("session") as LocalSession if main != null else null
	var dead: bool = session != null and session.sim.reactor != null and session.sim.reactor.destroyed
	return judge_view(view, dead, measurements)


## [result, message] for `view` with the reactor `dead` or not, adding the
## uniform's parts to `measurements`.
static func judge_view(view: LevelView, dead: bool, measurements: Dictionary) -> Array:
	if view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no level"]
	var walls: MeltdownWalls = view.meltdown_walls
	if walls.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the meltdown look was rejected: %s" % walls.error]
	if not walls.enabled:
		return [AcceptanceReport.RESULT_FAIL, "the level look has no meltdown section"]
	if not dead:
		return [AcceptanceReport.RESULT_FAIL, "the reactor is not dead at the end of the step"]
	var value: Vector3 = walls.value()
	measurements["meltdown_ramp"] = snappedf(value.x, 0.0001)
	measurements["meltdown_emission"] = snappedf(value.y, 0.0001)
	measurements["meltdown_strip_brightness"] = snappedf(value.z, 0.0001)
	var shown: String = "ramp %.3f, emission %.3f, strips at %.3f" % [value.x, value.y, value.z]
	if value.x <= 0.0 or value.y <= 0.0:
		return [AcceptanceReport.RESULT_FAIL, "the walls show no meltdown: " + shown]
	if value.y > MeltdownWallRules.MAX_EMISSION:
		return [AcceptanceReport.RESULT_FAIL, "the walls glow above the cap %s: %s" % [MeltdownWallRules.MAX_EMISSION, shown]]
	if value.z < 1.0 - MeltdownWallRules.MAX_STRIP_SWING or value.z > 1.0:
		return [AcceptanceReport.RESULT_FAIL, "the strips dim beyond the cap: " + shown]
	var checked: int = 0
	for box: int in view.box_count():
		for part: MeshInstance3D in [view.walls_of(box), view.bevels_of(box)]:
			if part == null or part.mesh == null:
				continue
			for surface: int in part.mesh.get_surface_count():
				var material: ShaderMaterial = part.mesh.surface_get_material(surface) as ShaderMaterial
				var drawn: Variant = material.get_shader_parameter(MeltdownWalls.PARAMETER) if material != null else null
				if not drawn is Vector3 or not (drawn as Vector3).is_equal_approx(value):
					return [AcceptanceReport.RESULT_FAIL, "box %d's %s draws meltdown %s, not %s" % [
						box, part.name, drawn, value]]
				checked += 1
	measurements["meltdown_surfaces"] = checked
	if checked == 0:
		return [AcceptanceReport.RESULT_FAIL, "the level draws no surface to carry the look"]
	return [AcceptanceReport.RESULT_PASS, "%s, on %d surfaces" % [shown, checked]]
