extends RefCounted

## Trapped miners drawn as beacons with a rescue hold ring (SLV-3, #1034, MP-2,
## ARC-4): the ring fills with the sim's hold count, a rescued miner's marker
## goes, and nothing is drawn while rescue is off.

const TestMinerRescue := preload("res://tests/test_miner_rescue.gd")


func _sim() -> Sim:
	# One miner 1 m ahead of the ship, well within the 4 m reach, and one far off.
	var miners: Array[Vector3i] = [Vector3i(0, 0, -1000), Vector3i(0, 0, -60000)]
	return TestMinerRescue.sim_with(miners)


func test_a_half_held_miner_shows_a_half_filled_ring() -> String:
	var sim: Sim = _sim()
	TestMinerRescue.idle(sim, TestMinerRescue.HOLD_TICKS / 2)
	var before: int = MinerRescue.state_hash(sim)
	var view: MinerView = MinerView.new()
	view.show_miners(sim.rescue, sim.ships[0])
	var problem: String = ""
	if view.shown_count() != 2:
		problem = "%d markers drawn" % view.shown_count()
	elif not is_equal_approx(view.fill_of(0), 0.5) or view.fill_of(1) != 0.0:
		problem = "fills %s and %s" % [view.fill_of(0), view.fill_of(1)]
	elif (view.marker(0).get_node("Ring/Fill") as MeshInstance3D).mesh == null:
		problem = "the half-held ring has no fill band"
	elif (view.marker(1).get_node("Ring/Fill") as MeshInstance3D).mesh != null:
		problem = "the unheld ring has a fill band"
	elif not view.marker(1).position.is_equal_approx(Vector3(0, 0, -60)):
		problem = "far miner drawn at %s" % view.marker(1).position
	elif MinerRescue.state_hash(sim) != before:
		problem = "drawing changed the rescue state"
	view.free()
	return problem


func test_a_rescued_miners_marker_is_gone() -> String:
	var sim: Sim = _sim()
	var view: MinerView = MinerView.new()
	view.show_miners(sim.rescue, sim.ships[0])
	TestMinerRescue.idle(sim, TestMinerRescue.HOLD_TICKS)
	view.show_miners(sim.rescue, sim.ships[0])
	var problem: String = ""
	if sim.rescue.rescued != 1:
		problem = "setup rescued %d" % sim.rescue.rescued
	elif view.shown_count() != 1 or not view.marker(0).position.is_equal_approx(Vector3(0, 0, -60)):
		problem = "%d markers after the rescue" % view.shown_count()
	view.free()
	return problem


func test_rescue_off_draws_nothing() -> String:
	var view: MinerView = MinerView.new()
	view.show_miners(Sim.new(1, 1).rescue, null)
	var count: int = view.marker_count()
	view.free()
	return "" if count == 0 else "%d markers with rescue off" % count


func test_the_arc_spans_its_share_of_a_turn() -> String:
	if MinerView.build_arc(1.0, 0.1, 0.0) != null:
		return "an empty fill built a band"
	var half: ArrayMesh = MinerView.build_arc(1.0, 0.1, 0.5)
	var full: ArrayMesh = MinerView.build_arc(1.0, 0.1, 1.0)
	var half_points: int = (half.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var full_points: int = (full.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var last: Vector3 = (half.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[half_points - 1]
	if half_points >= full_points or not last.is_equal_approx(Vector3(-1, 0, 0)):
		return "half arc has %d points ending at %s, full %d" % [half_points, last, full_points]
	return ""


func test_the_shipped_look_loads_and_a_bad_key_is_named() -> String:
	var view: MinerView = MinerView.new()
	var problem: String = view.look_error
	view.free()
	if problem != "":
		return problem
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE))
	var bad: Dictionary = {
		"beacon.radius": 0.0, "beacon.height": "tall", "beacon.color": [1, 1], "beacon.energy": true,
		"ring.radius": 9.0, "ring.width": 2.0, "ring.track_color": [0, 0, 3], "ring.fill_energy": -1,
	}
	for field: String in bad:
		var data: Dictionary = good.duplicate(true)
		var parts: PackedStringArray = field.split(".")
		data[parts[0]][parts[1]] = bad[field]
		var parsed: Dictionary = MinerView.parse_look(JSON.stringify(data))
		if not String(parsed.get("error", "")).contains(field):
			return "%s = %s: %s" % [field, JSON.stringify(bad[field]), parsed]
	var extra: Dictionary = good.duplicate(true)
	extra["figure"] = {}
	if not String(MinerView.parse_look(JSON.stringify(extra)).get("error", "")).contains("figure"):
		return "an unknown key was accepted"
	var missing: Dictionary = good.duplicate(true)
	missing["ring"].erase("width")
	return "" if String(MinerView.parse_look(JSON.stringify(missing)).get("error", "")).contains("ring.width") else "a missing key was accepted"


func test_the_main_scene_has_both_views() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var heaps: ComponentView = main.get_node_or_null(ComponentView.NODE_NAME) as ComponentView
	var miners: MinerView = main.get_node_or_null(MinerView.NODE_NAME) as MinerView
	var problem: String = ""
	if heaps == null or miners == null:
		problem = "views under the main scene: heaps %s, miners %s" % [heaps, miners]
	else:
		main.call("advance_frame", 1.0 / 90.0)
	main.free()
	return problem
