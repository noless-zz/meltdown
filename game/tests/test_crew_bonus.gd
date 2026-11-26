extends RefCounted

## The crew's salvage slots and seconds before meltdown reach the simulation
## (#1386, CRW-1, CRW-3, SLV-3, ARC-1, ARC-2): the hold grows by the riggers,
## capped; the countdown grows by the reactor hands after the level's clamp;
## a zero bonus changes nothing, hash included; the same seed, inputs and
## bonus give the same hash.

## A fixed copy of the roles, so the numbers below do not move when the
## shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""
const REACTOR: String = "{\"position\": [0, 0, -20], \"radius\": 2, \"hull\": 10, \"meltdown_seconds\": 90}"


func _bonus_of(role_ids: Array[String]) -> CrewBonus:
	var profile: Profile = Profile.new()
	for i: int in role_ids.size():
		profile.crew.append({Profile.CREW_ID: "crew-%d" % (i + 1), Profile.CREW_ROLE: role_ids[i]})
	return CrewBenefits.bonus(CrewBenefits.totals(profile, CrewRoles.parse_json(ROLES_TEXT)))


func _repeat(role: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for i: int in count:
		ids.append(role)
	return ids


func _sim_with_reactor(reactor_text: String = REACTOR) -> Sim:
	var sim: Sim = Sim.new(7, 2)
	sim.set_reactor(ReactorState.parse_json(reactor_text))
	return sim


## Ticks on the countdown once the reactor of a sim with `bonus` dies.
func _countdown(bonus: CrewBonus, reactor_text: String = REACTOR) -> int:
	var sim: Sim = _sim_with_reactor(reactor_text)
	if sim.set_crew_bonus(bonus) != "":
		return -1
	sim.reactor.apply_damage(100.0)
	return sim.reactor.meltdown_ticks_left


func _steps(sim: Sim, count: int) -> void:
	for tick: int in count:
		var inputs: Array[ShipInput] = []
		for index: int in sim.ships.size():
			var input: ShipInput = ShipInput.new()
			input.thrust_q = Vector3i(0, 0, -1000) if tick % 3 == 0 else Vector3i.ZERO
			input.fire_primary = tick % 5 == 0
			inputs.append(input)
		sim.step(inputs)


func test_hold_grows_by_riggers_up_to_the_cap() -> String:
	for riggers: int in [0, 1, 2, 3]:
		var bonus: CrewBonus = _bonus_of(_repeat("cargo_rigger", riggers))
		var want: int = ShipState.HOLD_CAPACITY + mini(riggers, 2)
		var sim: Sim = Sim.new(1, 2)
		if sim.set_crew_bonus(bonus) != "":
			return "%d riggers: the bonus was refused" % riggers
		for ship: ShipState in sim.ships:
			if ship.hold_capacity != want:
				return "%d riggers: hold %d, expected %d" % [riggers, ship.hold_capacity, want]
			for part: int in want:
				if not ship.hold_has_room():
					return "%d riggers: full after %d parts" % [riggers, part]
				ship.hold.append("pulse_cannon")
			if ship.hold_has_room():
				return "%d riggers: room after %d parts" % [riggers, want]
	return ""


func test_countdown_grows_by_reactor_hands_up_to_the_cap() -> String:
	for hands: int in [0, 1, 4, 5]:
		var seconds: int = mini(hands * 5, 20)
		var bonus: CrewBonus = _bonus_of(_repeat("reactor_hand", hands))
		if bonus.meltdown_seconds != seconds:
			return "%d hands gave %d s, expected %d" % [hands, bonus.meltdown_seconds, seconds]
		var ticks: int = _countdown(bonus)
		if ticks != (90 + seconds) * ReactorState.TICKS_PER_SECOND:
			return "%d s: countdown %d ticks" % [seconds, ticks]
	return ""


func test_countdown_seconds_are_added_after_the_level_clamp() -> String:
	# base 10 + 1 s/m over no path, clamped to 30..40: 30 s before the crew.
	var scaled: String = REACTOR.replace("}", ", \"meltdown_base_seconds\": 10, " \
		+ "\"meltdown_seconds_per_metre\": 1, \"meltdown_min_seconds\": 30, \"meltdown_max_seconds\": 40}")
	var sim: Sim = _sim_with_reactor(scaled)
	sim.set_crew_bonus(CrewBonus.of(0, 20))
	var none: int = sim.reactor.meltdown_ticks_for_path(0)
	var far: int = sim.reactor.meltdown_ticks_for_path(500000)
	if none != 50 * 60 or far != 60 * 60:
		return "clamped then crew: %d and %d ticks, expected 3000 and 3600" % [none, far]
	return ""


func test_a_zero_bonus_changes_nothing() -> String:
	var plain: Sim = _sim_with_reactor()
	var zero: Sim = _sim_with_reactor()
	if zero.set_crew_bonus(_bonus_of([])) != "" or zero.set_crew_bonus(_bonus_of(["shield_tech"])) != "":
		return "a zero bonus was refused"
	if zero.crew != null or zero.ships[0].hold_capacity != ShipState.HOLD_CAPACITY \
			or zero.reactor.crew_seconds != 0:
		return "a zero bonus was installed"
	_steps(plain, 90)
	_steps(zero, 90)
	return "" if plain.state_hash() == zero.state_hash() else "a zero bonus changed the hash"


func test_same_seed_inputs_and_bonus_give_the_same_hash() -> String:
	var hashes: Array[int] = []
	for bonus: CrewBonus in [CrewBonus.of(2, 20), CrewBonus.of(2, 20), CrewBonus.of(1, 20)]:
		var sim: Sim = _sim_with_reactor()
		sim.set_crew_bonus(bonus)
		_steps(sim, 90)
		hashes.append(sim.state_hash())
	var plain: Sim = _sim_with_reactor()
	_steps(plain, 90)
	if hashes[0] != hashes[1]:
		return "the same bonus gave two hashes"
	if hashes[0] == hashes[2] or hashes[0] == plain.state_hash():
		return "the bonus is not in the hash"
	return ""


func test_the_bonus_is_set_only_before_the_first_tick() -> String:
	var sim: Sim = _sim_with_reactor()
	_steps(sim, 1)
	if sim.set_crew_bonus(CrewBonus.of(1, 5)) == "" or sim.crew != null:
		return "a bonus was installed after the first tick"
	return ""


func test_bad_values_are_refused() -> String:
	var cases: Dictionary = {
		"[1]": "must be a JSON object",
		"{\"hold_slots\": 1}": "key \"meltdown_seconds\" must be a whole number",
		"{\"hold_slots\": 1.5, \"meltdown_seconds\": 0}": "key \"hold_slots\" must be a whole number",
		"{\"hold_slots\": -1, \"meltdown_seconds\": 0}": "key \"hold_slots\" must be 0 to 16",
		"{\"hold_slots\": 0, \"meltdown_seconds\": 601}": "key \"meltdown_seconds\" must be 0 to 600",
		"{\"hold_slots\": 0, \"meltdown_seconds\": 0, \"map\": 1}": "unknown key \"map\"",
	}
	for text: String in cases:
		var bonus: CrewBonus = CrewBonus.parse_json(text)
		if bonus.error != cases[text]:
			return "%s: got '%s'" % [text, bonus.error]
	var sim: Sim = Sim.new(1, 1)
	if sim.set_crew_bonus(CrewBonus.parse_json("[1]")) == "" or sim.crew != null:
		return "a rejected bonus was installed"
	return ""
