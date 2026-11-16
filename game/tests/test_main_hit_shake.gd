extends RefCounted

## The hit shake wired into the main scene (#169; CMF-1, CMF-3, CMF-6, ARC-3,
## MP-2): the session hands on every tick's events, the shake follows the
## active preset, and the rig shows its offset on top of the ship's pose.

const FRAME: float = 1.0 / 90.0
## Straight down into the test tunnel's floor, which the ship starts touching.
const DIVE: Vector3 = Vector3(0.0, -12.0, 0.0)


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


static func _idle(main: Node, delta: float = FRAME) -> void:
	main.call("apply_controls", ControllerSampler.idle_values())
	main.call("advance_frame", delta)


## Starts the ship moving into the floor. A test may write simulation state;
## the scene never does.
static func _dive(main: Node) -> void:
	(main.get("session") as LocalSession).sim.ships[0].velocity = DIVE


## The rig transform `place_rig` would give without any shake.
static func _plain_pose(main: Node) -> Transform3D:
	var session: LocalSession = main.get("session")
	var comfort: ComfortWiring = main.get("comfort")
	var recentre: HeadRecentre = main.get("head_recentre")
	return recentre.rig_transform(ComfortWiring.interpolated_pose(session.previous_ship(),
		session.current_ship(), session.interpolation_fraction, comfort.latest_tick_snapped))


static func _rig(main: Node) -> Transform3D:
	return (main.get_node("XRRig") as Node3D).transform


static func _has_impact(events: Array[SimEvent]) -> bool:
	for event: SimEvent in events:
		if event.kind == SimEvent.Kind.WALL_IMPACT:
			return true
	return false


func test_frame_events_hold_every_tick_of_an_advance() -> String:
	var input: ShipInput = ShipInput.new()
	input.afterburner = true
	var source: LatestInputSource = LatestInputSource.new()
	source.set_input(input)
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Vector3(0.0, -1.0, 0.0)))
	session.sim.ships[0].velocity = DIVE
	# Three ticks: the boost starts on the first and the floor is hit on it too.
	if session.advance(3.0 * ShipState.TICK_DT) != 3:
		return "advance ran %d ticks, not 3" % session.ticks_last_advance
	var events: Array[SimEvent] = session.frame_events()
	if events.is_empty() or events[0].kind != SimEvent.Kind.AFTERBURNER_STARTED:
		return "the first tick's boost start is missing: %s" % [events]
	if not _has_impact(events):
		return "the wall impact is missing: %s" % [events]
	if events.size() == session.sim.last_events.size():
		return "frame_events holds only the last tick: %s" % [events]
	events.clear()
	if session.frame_events().is_empty():
		return "clearing the returned list emptied the session's"
	session.advance(0.0)
	if not session.frame_events().is_empty():
		return "an advance that ran no tick kept %s" % [session.frame_events()]
	return ""


func test_preset_1_never_moves_the_rig_on_a_hit() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 1)
	_dive(main)
	var hit: bool = false
	for frame: int in 60:
		_idle(main)
		hit = hit or _has_impact((main.get("session") as LocalSession).frame_events())
		if _rig(main) != _plain_pose(main):
			main.free()
			return "preset 1 moved the rig on frame %d" % frame
	main.free()
	return "" if hit else "the ship never hit the floor"


func test_preset_3_shakes_then_returns_to_the_pose() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 3)
	var shake: HitShake = (main.get("comfort") as ComfortWiring).hit_shake
	if shake == null:
		main.free()
		return "the shipped hit-shake file was rejected"
	# The main scene's robots shoot the ship from the start (#269); their hits
	# would keep restarting the shake this test waits to settle.
	for robot: RobotState in (main.get("session") as LocalSession).sim.robots:
		robot.weapon = null
	_dive(main)
	var moved: bool = false
	var frame: int = 0
	while frame < 30 and not moved:
		_idle(main)
		moved = _rig(main) != _plain_pose(main)
		frame += 1
	if not moved:
		main.free()
		return "a wall impact under preset 3 never moved the rig"
	if _rig(main).basis.get_rotation_quaternion().angle_to(_plain_pose(main).basis.get_rotation_quaternion()) > 1e-5:
		main.free()
		return "preset 3 rolled the rig without hit_spin"
	# Stop the ship where it is, so no later impact restarts the shake.
	(main.get("session") as LocalSession).sim.ships[0].velocity = Vector3.ZERO
	var elapsed: float = 0.0
	while elapsed < shake.decay_s:
		_idle(main)
		elapsed += FRAME
	var settled: bool = _rig(main) == _plain_pose(main)
	main.free()
	if not settled:
		return "the rig was still off the pose %f s after the hit" % elapsed
	return ""


func test_preset_4_also_rolls_the_rig() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 4)
	_dive(main)
	var rolled: bool = false
	for frame: int in 30:
		_idle(main)
		var turn: float = _rig(main).basis.get_rotation_quaternion().angle_to(
			_plain_pose(main).basis.get_rotation_quaternion())
		rolled = rolled or turn > 1e-4
	main.free()
	return "" if rolled else "a wall impact under preset 4 did not roll the rig"


func test_a_preset_change_reaches_the_shake() -> String:
	var main: Node = _main()
	var comfort: ComfortWiring = main.get("comfort")
	if comfort.hit_shake == null or comfort.hit_shake.preset != comfort.preset:
		main.free()
		return "the shake does not start on the active preset"
	for number: int in [1, 4, 3]:
		main.call("set_comfort_preset", number)
		if comfort.hit_shake.preset != comfort.preset or comfort.hit_shake.preset.hit_shake != comfort.preset.hit_shake:
			main.free()
			return "preset %d did not reach the shake" % number
	main.free()
	return ""


func test_a_rejected_file_leaves_the_shake_off() -> String:
	if ComfortWiring.load_hit_shake("res://xr/no_such_file.json") != null:
		return "a missing file gave a shake"
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.hit_shake = null
	comfort.feed_hit_shake([SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 30.0, Vector3.UP)], 0, Basis.IDENTITY)
	comfort.advance_hit_shake(FRAME)
	if comfort.shake_offset != Transform3D.IDENTITY:
		return "no shake still moved the view"
	return ""


## ARC-3, MP-2: feeding the shake and drawing it leave the simulation as a run
## without the shake would: the replay of the session reproduces it.
func test_the_shake_writes_no_simulation_state() -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", 4)
	var hit: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 30.0, Vector3.RIGHT)]
	for frame: int in 40:
		if frame % 10 == 0:
			(main.get("comfort") as ComfortWiring).feed_hit_shake(hit, 0, Basis.IDENTITY)
		_idle(main)
	var session: LocalSession = main.get("session")
	var hash_with_view: int = session.sim.state_hash()
	var replayed: Sim = session.replay.run()
	main.free()
	if replayed == null or replayed.state_hash() != hash_with_view:
		return "the session no longer matches its replay"
	return ""
