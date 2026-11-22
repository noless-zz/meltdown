extends RefCounted

## `SimRules`, what a run fixes before its first tick, driven directly (#1154,
## ARC-1, ARC-2): defaults, each setter taking a valid value, refusing a broken
## one and refusing anything once locked, and `Sim` reading through to it.

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"


func _cannon() -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))


func _box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -10, -10), Vector3(10, 10, 10))]
	return BoxUnion.new(boxes)


func test_defaults_are_open_space_default_rules_and_no_parts() -> String:
	var rules: SimRules = SimRules.new()
	if rules.walls != null or rules.bounds != null:
		return "a new SimRules has walls"
	if rules.salvage_rules == null or rules.salvage_rules.values_hash() != SalvageRules.new().values_hash():
		return "the default salvage rules are not SalvageRules.new()"
	if rules.look_aim == null or rules.look_aim.values_hash() != LookAim.new().values_hash():
		return "the default look-aim is not LookAim.new()"
	if rules.aim_assist == null or rules.aim_assist.cone_degrees != AimAssist.new().cone_degrees \
			or rules.aim_assist.range_m != AimAssist.new().range_m:
		return "the default aim assist is not AimAssist.new()"
	if not rules.part_ids().is_empty() or rules.part("pulse_cannon") != null:
		return "a new SimRules has parts"
	return ""


func test_walls_set_their_first_box_and_refuse_empty_or_locked() -> String:
	var rules: SimRules = SimRules.new()
	var walls: BoxUnion = _box()
	if not rules.set_walls(walls, false) or rules.walls != walls or rules.bounds != walls.boxes[0]:
		return "valid walls were not taken"
	if rules.set_walls(BoxUnion.new(), false) or rules.walls != walls:
		return "a union with no boxes was taken"
	if rules.set_walls(null, true) or rules.walls != walls:
		return "walls changed while locked"
	if not rules.set_walls(null, false) or rules.walls != null or rules.bounds != null:
		return "open space was refused"
	return ""


func test_parts_are_checked_sorted_and_kept_whole_on_a_problem() -> String:
	var rules: SimRules = SimRules.new()
	if rules.set_parts({"pulse_cannon": _cannon(), "arc_cannon": _cannon()}, false) != "":
		return "a valid catalogue was refused"
	var expected: Array[String] = ["arc_cannon", "pulse_cannon"]
	if rules.part_ids() != expected:
		return "part ids %s are not sorted" % [rules.part_ids()]
	var broken: WeaponDef = WeaponDef.parse_json("[]")
	if rules.set_parts({"spare": _cannon(), "bad": broken}, false).find("bad") == -1:
		return "an unresolved weapon was not named"
	if rules.set_parts({"spare": _cannon()}, true) == "" or rules.part("spare") != null:
		return "the catalogue changed while locked or after a problem"
	if rules.part("pulse_cannon") == null:
		return "the catalogue lost a part"
	return ""


func test_salvage_rules_take_resolved_rules_only_while_unlocked() -> String:
	var rules: SimRules = SimRules.new()
	var wide: SalvageRules = SalvageRules.parse_json(JSON.stringify(
		{"pickup_reach": 2.0, "pull_reach": 6.0, "pull_speed": 5.0, "swap_drop_distance": 3.0}))
	if rules.set_salvage_rules(wide, false) != "" or rules.salvage_rules != wide:
		return "valid salvage rules were refused"
	if rules.set_salvage_rules(SalvageRules.parse_json("[]"), false) == "" \
			or rules.set_salvage_rules(null, false) == "" \
			or rules.set_salvage_rules(SalvageRules.new(), true) == "" or rules.salvage_rules != wide:
		return "broken or locked salvage rules were taken"
	return ""


func test_look_aim_takes_resolved_values_only_while_unlocked() -> String:
	var rules: SimRules = SimRules.new()
	var wide: LookAim = LookAim.parse_json("{\"cone_degrees\": 90, \"gimbal_degrees_per_second\": 360}")
	if rules.set_look_aim(wide, false) != "" or rules.look_aim != wide:
		return "a valid look-aim was refused"
	if rules.set_look_aim(LookAim.parse_json("[]"), false) == "" \
			or rules.set_look_aim(LookAim.new(), true) == "" or rules.look_aim != wide:
		return "a broken or locked look-aim was taken"
	return ""


func test_aim_assist_takes_resolved_values_only_while_unlocked() -> String:
	var rules: SimRules = SimRules.new()
	var narrow: AimAssist = AimAssist.new()
	narrow.cone_degrees = 3.0
	if rules.set_aim_assist(narrow, false) != "" or rules.aim_assist != narrow:
		return "a valid aim assist was refused"
	if rules.set_aim_assist(AimAssist.parse_json("[]"), false) == "" \
			or rules.set_aim_assist(AimAssist.new(), true) == "" or rules.aim_assist != narrow:
		return "a broken or locked aim assist was taken"
	return ""


func test_sim_reads_through_and_locks_after_the_first_tick() -> String:
	var sim: Sim = Sim.new(1, 1, BoxBounds.new(Vector3(-5, -5, -5), Vector3(5, 5, 5)))
	if sim.walls != sim.rules.walls or sim.bounds != sim.rules.bounds or sim.bounds == null:
		return "Sim's walls do not read through to its rules"
	var assist: AimAssist = AimAssist.new()
	if sim.set_aim_assist(assist) != "" or sim.aim_assist != assist:
		return "Sim did not pass aim assist to its rules"
	var inputs: Array[ShipInput] = [ShipInput.new()]
	sim.step(inputs)
	if sim.set_walls(_box()) or sim.set_look_aim(LookAim.new()) == "" \
			or sim.set_parts({"pulse_cannon": _cannon()}) != "the part catalogue is set before the first tick":
		return "Sim's rules changed after the first tick"
	return ""
