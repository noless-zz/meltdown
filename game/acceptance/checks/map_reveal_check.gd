extends RefCounted

## The `map_reveal` check (#1393, CRW-1, MAP-1, MP-2, DEV-6), lane-a's file under
## `acceptance/checks/`. On a run step, before its moving check:
##
##     {"id": "pickup_look", "run": 12345, ...,
##      "checks": [..., "map_reveal", "crew_joins"]}
##
## It reads the scene's own wiring: the crew totals `LevelStart` hands the map
## for the run's level must be the run's crew totals and a copy, and the
## scene's map must reveal exactly when they hold `map_reveal`. It then starts
## two maps of its own on the flown level's session, as the first frame does
## (`MapWiring.begin`), with the totals of a crew without and with a Surveyor
## from the shipped roles file, and counts the boxes drawn: without, only the
## boxes the ship is in; with, every box of the level, the unflown ones on the
## dimmer surface. The scene's map and session are left as they were.

const CHECK: String = "map_reveal"
const SURVEYOR: String = "surveyor"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var main: Node = runner.main if runner != null else null
	if main == null:
		return [AcceptanceReport.RESULT_FAIL, "no main scene"]
	var map: MapWiring = main.get("map") as MapWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var session: LocalSession = main.get("session") as LocalSession
	if map == null or level_start == null or session == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no map, level start or session"]
	return judge(map, level_start, session, measurements)


## The verdict for the scene's `map`, `level_start` and the run level's `session`.
static func judge(map: MapWiring, level_start: LevelStart, session: LocalSession,
		measurements: Dictionary) -> Array:
	var run: RunWiring = level_start.run
	if run == null or not run.active():
		return [AcceptanceReport.RESULT_FAIL, "the step flies no run; map_reveal needs a run step"]
	var handed: Dictionary = level_start.crew_totals_for(session)
	var expected: Dictionary = CrewBenefits.totals(run.profile, run.roles)
	if handed != expected:
		return [AcceptanceReport.RESULT_FAIL, "the map was handed crew totals %s, the run's crew gives %s" % [
			handed, expected]]
	var wants_reveal: bool = int(expected.get(MapWiring.REVEAL_STAT, 0)) >= 1
	if map.revealed != wants_reveal:
		return [AcceptanceReport.RESULT_FAIL, "the scene's map reveal is %s with crew totals %s" % [
			map.revealed, expected]]
	var walls: BoxUnion = session.replay.walls()
	var boxes: int = walls.boxes.size() if walls != null else 0
	if boxes < 2:
		return [AcceptanceReport.RESULT_FAIL, "the run's level has %d boxes; the check needs a level" % boxes]
	var hash_before: int = session.sim.state_hash()
	var plain: Dictionary = _first_frame(session, _totals(run.roles, []))
	var surveyed: Dictionary = _first_frame(session, _totals(run.roles, [SURVEYOR]))
	measurements["map_boxes"] = boxes
	measurements["map_boxes_plain"] = plain["boxes"]
	measurements["map_boxes_revealed"] = surveyed["boxes"]
	if session.sim.state_hash() != hash_before:
		return [AcceptanceReport.RESULT_FAIL, "starting a map changed the session's state (MP-2)"]
	if plain["revealed"] or plain["boxes"] < 1 or plain["boxes"] >= boxes or plain["dim"] != 0:
		return [AcceptanceReport.RESULT_FAIL, "without a Surveyor the first frame drew %d of %d boxes, %d dim lines" % [
			plain["boxes"], boxes, plain["dim"]]]
	if not surveyed["revealed"] or surveyed["boxes"] != boxes or surveyed["dim"] == 0 \
			or surveyed["lines"] != plain["lines"]:
		return [AcceptanceReport.RESULT_FAIL, "with a Surveyor the first frame drew %d of %d boxes, %d explored lines (%d without), %d dim" % [
			surveyed["boxes"], boxes, surveyed["lines"], plain["lines"], surveyed["dim"]]]
	return [AcceptanceReport.RESULT_PASS, "first frame: %d of %d boxes without a Surveyor, all %d with one (%d dim lines); scene's map handed %s" % [
		plain["boxes"], boxes, boxes, surveyed["dim"], handed]]


## Crew totals for a crew of `roles_held`, from the shipped roles.
static func _totals(roles: CrewRoles, roles_held: Array[String]) -> Dictionary:
	var profile: Profile = Profile.new()
	for i: int in roles_held.size():
		profile.crew.append({Profile.CREW_ID: "check_%d" % i, Profile.CREW_ROLE: roles_held[i]})
	return CrewBenefits.totals(profile, roles)


## A map of its own started on `session` with `totals`, as its first frame:
## boxes drawn, whether it revealed, and its explored and dim line counts.
static func _first_frame(session: LocalSession, totals: Dictionary) -> Dictionary:
	var probe: MapWiring = MapWiring.new()
	probe.hologram = MapHologram.new()
	probe.crew_totals = func(_s: LocalSession) -> Dictionary: return totals.duplicate()
	probe.begin(session)
	var result: Dictionary = {"boxes": probe.start_boxes, "revealed": probe.revealed,
		"lines": probe.hologram.segment_count(), "dim": probe.hologram.revealed_segment_count()}
	probe.hologram.free()
	return result
