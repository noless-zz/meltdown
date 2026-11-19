extends RefCounted

## The ring that shows when a floating part is within reach (#600, SLV-1,
## LGT-1, MP-2).

const LOOK_FILE: String = "res://view/salvage_look.json"


func _rules() -> SalvageRules:
	return SalvageRules.parse_json(JSON.stringify({"pickup_reach": 2.5, "pull_reach": 9.0,
		"pull_speed": 8.0, "swap_drop_distance": 4.0}))


func test_shipped_look_has_a_ring_and_still_parses_for_the_parts() -> String:
	var text: String = FileAccess.get_file_as_string(LOOK_FILE)
	var ring: Dictionary = SalvageRing.parse_look(text)
	if ring.has("error"):
		return ring["error"]
	if SalvageView.parse_look(text).has("error"):
		return "the part look no longer parses: %s" % SalvageView.parse_look(text)["error"]
	if ring["near_energy"] <= ring["far_energy"]:
		return "the ring does not brighten within reach"
	return ""


func test_bad_ring_entries_are_rejected() -> String:
	var cases: Dictionary = {
		"{}": "\"ring\" must be an object",
		"{\"ring\": {\"radius\": 0.9, \"color\": [1, 1, 1], \"far_energy\": 2, \"near_energy\": 1}}":
			"\"ring.near_energy\" must be at least far_energy",
		"{\"ring\": {\"radius\": 9, \"color\": [1, 1, 1], \"far_energy\": 0, \"near_energy\": 1}}":
			"\"ring.radius\" is 9",
		"{\"ring\": {\"radius\": 1, \"color\": [1, 1], \"far_energy\": 0, \"near_energy\": 1}}":
			"\"ring.color\" must be [red, green, blue]",
		"{\"ring\": {\"radius\": 1, \"colour\": [1, 1, 1], \"far_energy\": 0, \"near_energy\": 1}}":
			"\"ring\" has unknown key \"colour\"",
	}
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var look: Dictionary = SalvageRing.parse_look(text)
		if not str(look.get("error", "")).begins_with(cases[text]):
			failures.append("%s: got %s" % [text, look])
	return "\n".join(failures)


func test_brightness_follows_the_reach() -> String:
	var ring: SalvageRing = SalvageRing.new()
	var look: Dictionary = SalvageRing.parse_look(FileAccess.get_file_as_string(LOOK_FILE))
	var ship: ShipState = ShipState.new()
	var rules: SalvageRules = _rules()
	var near: float = ring.energy_for(SalvageItem.new("x", Vector3(0.0, 0.0, -3.4)), ship, rules)
	var middle: float = ring.energy_for(SalvageItem.new("x", Vector3(0.0, 0.0, -6.0)), ship, rules)
	var far: float = ring.energy_for(SalvageItem.new("x", Vector3(0.0, 0.0, -12.0)), ship, rules)
	ship.hold.append("needle_gun")
	var full: float = ring.energy_for(SalvageItem.new("x", Vector3(0.0, 0.0, -3.4)), ship, rules)
	ring.free()
	if near != look["near_energy"] or far != look["far_energy"] or full != look["far_energy"]:
		return "near %s, far %s, full hold %s" % [near, far, full]
	if not (middle < near and middle > far):
		return "inside the pull range the ring is %s, not between %s and %s" % [middle, far, near]
	return ""


func test_one_ring_per_part_facing_the_ship_and_pooled() -> String:
	var ring: SalvageRing = SalvageRing.new()
	var ship: ShipState = ShipState.new()
	var items: Array[SalvageItem] = [SalvageItem.new("a", Vector3(0.0, 0.0, -5.0)),
		SalvageItem.new("b", Vector3(4.0, 0.0, 0.0))]
	var before: int = items[0].state_hash()
	ring.show_rings(items, items, 0.5, ship, _rules())
	var problem: String = ""
	if ring.node_count() != 2 or not ring.node(0).visible or not ring.node(1).visible:
		problem = "%d rings, expected 2 shown" % ring.node_count()
	elif ring.node(0).position != items[0].position:
		problem = "ring 0 at %s, part at %s" % [ring.node(0).position, items[0].position]
	elif ring.node(0).basis.y.normalized().distance_to(Vector3(0.0, 0.0, 1.0)) > 1e-4:
		problem = "ring 0's axis is %s, not towards the ship" % ring.node(0).basis.y
	elif items[0].state_hash() != before:
		problem = "drawing changed a part"
	if problem == "":
		ring.show_rings(items, [items[0]] as Array[SalvageItem], 1.0, ship, _rules())
		if ring.node_count() != 2 or ring.node(1).visible:
			problem = "a taken part's ring is still shown"
	ring.free()
	return problem


func test_the_main_scene_draws_rings_beside_the_parts() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var ring: SalvageRing = main.get_node_or_null(SalvageRing.NODE_NAME) as SalvageRing
	var problem: String = ""
	if ring == null:
		problem = "no SalvageRing under the main scene"
	else:
		var session: LocalSession = main.get("session")
		session.sim.robots[0].hull = 0.0
		for i: int in 3:
			main.call("advance_frame", 1.0 / 90.0)
		if session.current_salvage().size() != 1 or ring.node_count() != 1 or not ring.node(0).visible:
			problem = "%d parts and %d rings after a robot was destroyed" % [
				session.current_salvage().size(), ring.node_count()]
	main.free()
	return problem
