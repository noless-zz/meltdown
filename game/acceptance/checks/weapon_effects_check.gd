extends RefCounted

## The `weapon_effects_shown` acceptance check (#1309, GFX-2, GFX-4, GFX-6,
## ARC-1): re-flies the step's replay tick by tick and shows its bolts with the
## shipped look as the game does, from copies, so the simulation is only read.
## It passes when each weapon fired drew its own bolt mesh, a wall strike
## sparked and scorched, a hit on a robot and a hit on the ship each burst,
## the bolt lights never passed `max_lights`, and the flight still ends on the
## step's pinned hash. The screenshots of the step show the same in pictures.

const CHECK: String = "weapon_effects_shown"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the replay was refused: %s" % replay.error]
	var view: ProjectileView = ProjectileView.new()
	if view.look_error != "":
		view.free()
		return [AcceptanceReport.RESULT_FAIL, "the look was rejected: %s" % view.look_error]
	var flown: Dictionary = fly(replay, view)
	var impacts: BoltImpacts = view.impacts
	var counts: Dictionary = {
		"weapon_meshes": flown.get("meshes", 0), "most_lights": flown.get("most_lights", 0),
		"wall_sparks": impacts.wall_sparks.pool_size(), "scorches": impacts.scorches.shown().size(),
		"hit_sparks": impacts.hit_sparks.pool_size(), "hit_flashes": impacts.hit_flashes.pool_size(),
	}
	var budget: int = view.max_lights
	view.free()
	if flown.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	measurements.merge(counts, true)
	if step.expected_hash != AcceptanceStep.NO_HASH and flown["hash"] != step.expected_hash:
		return [AcceptanceReport.RESULT_FAIL, "drawn with the effects the hash is %d, not %d"
			% [flown["hash"], step.expected_hash]]
	if int(counts["weapon_meshes"]) < int(flown["weapons"]):
		return [AcceptanceReport.RESULT_FAIL, "%d weapons fired but %d bolt meshes drawn"
			% [flown["weapons"], counts["weapon_meshes"]]]
	if int(counts["most_lights"]) > budget:
		return [AcceptanceReport.RESULT_FAIL, "%d bolt lights at once, budget %d" % [counts["most_lights"], budget]]
	for key: String in ["wall_sparks", "scorches", "hit_flashes"]:
		if int(counts[key]) < 1:
			return [AcceptanceReport.RESULT_FAIL, "no %s over the firefight: %s" % [key, counts]]
	if int(counts["hit_sparks"]) < 2:
		return [AcceptanceReport.RESULT_FAIL, "the robot and ship hits did not both burst: %s" % [counts]]
	return [AcceptanceReport.RESULT_PASS, "%s" % [counts]]


## Flies `replay` showing its bolts in `view` each tick. Returns the final
## hash (`hash`), the weapons fired (`weapons`), the distinct bolt meshes drawn
## (`meshes`) and the most bolt lights lit at once (`most_lights`); empty when
## the replay cannot start.
static func fly(replay: Replay, view: ProjectileView) -> Dictionary:
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return {}
	var copies: Dictionary[Projectile, Projectile] = {}
	var weapons: Dictionary[String, bool] = {}
	var meshes: Dictionary[Mesh, bool] = {}
	var most_lights: int = 0
	for frame: Array in frames:
		var before: Array[RobotState] = []
		for robot: RobotState in sim.robots:
			before.append(RobotState.new(robot.def, robot.position))
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		sim.step(inputs)
		var shown: Array[Projectile] = []
		var kept: Dictionary[Projectile, Projectile] = {}
		for projectile: Projectile in sim.projectiles:
			var copy: Projectile = copies.get(projectile, null)
			if copy == null:
				copy = Projectile.new(projectile.position, projectile.velocity, projectile.owner_index,
					projectile.ticks_left, projectile.damage)
				copy.slot = projectile.slot
				weapons[ProjectileWeaponLooks.weapon_of(copy, sim.ships, before, view.weapon_rows())] = true
			copy.position = projectile.position
			copy.velocity = projectile.velocity
			copy.ticks_left = projectile.ticks_left
			kept[projectile] = copy
			shown.append(copy)
		copies = kept
		var poses: Array[Transform3D] = []
		for ship: ShipState in sim.ships:
			poses.append(Transform3D(ship.orientation, ship.position))
		view.set_scene(sim.ships, before, sim.walls)
		if not poses.is_empty():
			view.set_viewer(poses[0].origin)
		view.show_projectiles(shown, 1.0, poses)
		for index: int in shown.size():
			meshes[view.bolt(index).mesh] = true
		most_lights = maxi(most_lights, view.lit_bolts().size())
	return {"hash": sim.state_hash(), "weapons": weapons.size(), "meshes": meshes.size(),
		"most_lights": most_lights}
