extends RefCounted

## The hit cue in the main scene (#618; CMB-2, CMF-1, CMF-8, PLT-6, ARC-3):
## a robot's shot on the local ship from its right reaches the edge flash, the bar flash, the
## right hand's pulse and `HitShake` on every preset; preset 1 still never moves the
## view; and a part flown through gives the pickup pulse.

const FRAME: float = 1.0 / 90.0
## The shot `_until_hit` fires lands within a few ticks.
const MAX_FRAMES: int = 60


func _main() -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	return main


static func _ship_hits(main: Node) -> int:
	var hits: int = 0
	for event: SimEvent in (main.get("session") as LocalSession).frame_events():
		if event.ship == 0 and event.kind == SimEvent.Kind.SHIP_HIT:
			hits += 1
	return hits


static func _fill_color(panel: StatusPanel, bar_name: String) -> Color:
	return ((panel.get_node(bar_name) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color


## Fires a robot's shot at the ship from its right, then flies idle frames
## until it hits; returns the frame, or -1. A test may write simulation state;
## the scene never does.
static func _until_hit(main: Node) -> int:
	var sim: Sim = (main.get("session") as LocalSession).sim
	var ship: ShipState = sim.ships[0]
	sim.projectiles.append(Projectile.new(ship.position + ship.orientation.x * 0.9,
		-ship.orientation.x * 30.0, Projectile.robot_owner(0), 60, 6.0))
	for frame: int in MAX_FRAMES:
		main.call("apply_controls", ControllerSampler.idle_values())
		main.call("advance_frame", FRAME)
		if _ship_hits(main) > 0:
			return frame
	return -1


func test_a_robot_hit_reaches_every_cue_on_every_preset() -> String:
	for number: int in range(1, 5):
		var message: String = _hit_on_preset(number)
		if message != "":
			return "preset %d: %s" % [number, message]
	return ""


func _hit_on_preset(number: int) -> String:
	var main: Node = _main()
	main.call("set_comfort_preset", number)
	var combat: CombatWiring = main.get("combat")
	var comfort: ComfortWiring = main.get("comfort")
	var panel: StatusPanel = main.get("status_panel")
	var hands: Array[String] = []
	var hit_s: float = HapticsSpec.load_file().pulse_for(HapticsSpec.SHIP_HIT)["duration_s"]
	combat.hit_haptics.request_hook = func(hand: String, pulse: Dictionary) -> void:
		if pulse["duration_s"] == hit_s:
			hands.append(hand)
	var frame: int = _until_hit(main)
	var message: String = ""
	if frame < 0:
		message = "no robot hit the ship in %d frames" % MAX_FRAMES
	elif combat.hit_overlay == null or combat.hit_overlay.lit_sides() != ([HitFlash.RIGHT] as Array[String]):
		message = "a shot from the right lit %s" % [combat.hit_overlay.lit_sides() if combat.hit_overlay != null else []]
	elif combat.hit_overlay.get_parent() != main.get_node("XRRig/Camera"):
		message = "the edge strips are not under the camera"
	elif hands != (["right"] as Array[String]):
		message = "a shot from the right pulsed %s" % [hands]
	elif _fill_color(panel, StatusPanel.SHIELD_BAR_NAME) == StatusPanel.SHIELD_COLOR \
			and _fill_color(panel, StatusPanel.HULL_BAR_NAME) == StatusPanel.HULL_COLOR:
		message = "neither bar flashed"
	elif comfort.hit_shake == null or not comfort.hit_shake.strength() > 0.0:
		message = "the hit did not reach HitShake"
	elif number == 1 and comfort.shake_offset != Transform3D.IDENTITY:
		message = "preset 1 shook the view"
	if message == "":
		# Once the flash has run out, the edge and the bars are back to plain.
		var sim: Sim = (main.get("session") as LocalSession).sim
		for robot: RobotState in sim.robots:
			robot.weapon = null
		sim.projectiles.clear()  # A test may write simulation state; the scene never does.
		for i: int in 60:
			main.call("advance_frame", FRAME)
		if not combat.hit_overlay.lit_sides().is_empty():
			message = "the edge still shows %s after the flash" % [combat.hit_overlay.lit_sides()]
		elif _fill_color(panel, StatusPanel.SHIELD_BAR_NAME) != StatusPanel.SHIELD_COLOR:
			message = "the shield bar kept the flash"
	main.free()
	return message


func test_the_cue_writes_no_simulation_state() -> String:
	var main: Node = _main()
	var combat: CombatWiring = main.get("combat")
	var hit: Array[SimEvent] = [SimEvent.new(SimEvent.Kind.SHIP_HIT, 0, 6.0, Vector3.LEFT),
		SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, 0, 0.0, Vector3.ZERO)]
	for frame: int in 40:
		if frame % 10 == 0:
			var session_now: LocalSession = main.get("session")
			combat.feed_events(hit, session_now.current_ship(), false)
		main.call("apply_controls", ControllerSampler.idle_values())
		main.call("advance_frame", FRAME)
	var session: LocalSession = main.get("session")
	var hash_with_view: int = session.sim.state_hash()
	var replayed: Sim = session.replay.run()
	main.free()
	if replayed == null or replayed.state_hash() != hash_with_view:
		return "the session no longer matches its replay"
	return ""


func test_a_part_flown_through_pulses_both_hands() -> String:
	var main: Node = _main()
	var combat: CombatWiring = main.get("combat")
	var pulses: Array[String] = []
	var pickup_s: float = HapticsSpec.load_file().pulse_for(HapticsSpec.SALVAGE_PICKUP)["duration_s"]
	combat.hit_haptics.request_hook = func(hand: String, pulse: Dictionary) -> void:
		if pulse["duration_s"] == pickup_s:
			pulses.append(hand)
	var session: LocalSession = main.get("session")
	session.sim.robots[0].hull = 0.0
	for robot: RobotState in session.sim.robots:
		robot.weapon = null
	for i: int in 3:
		main.call("advance_frame", FRAME)
	if session.current_salvage().is_empty():
		main.free()
		return "the destroyed robot dropped no part"
	var item: SalvageItem = session.current_salvage()[0]
	var ship: ShipState = session.sim.ships[0]
	ship.position = item.position + Vector3(0.0, 0.0, 4.0)
	ship.velocity = Vector3.ZERO
	(main.get("input_source") as LatestInputSource).set_input(ShipInput.new(Vector3i(0, 0, -ShipInput.SCALE)))
	for i: int in 90:
		main.call("advance_frame", FRAME)
	var hold: Array[String] = session.current_ship().hold.duplicate()
	main.free()
	if hold.is_empty():
		return "the ship never picked the part up"
	if pulses != (["left", "right"] as Array[String]):
		return "the pickup pulsed %s" % [pulses]
	return ""
