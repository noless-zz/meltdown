extends RefCounted

## Wall bounces pulse the hand on the wall's side, scaled by impact speed
## (#828; PLT-6, FLT-3, ARC-3, ARC-4, MP-2).

const VALID: String = """{
	"boost_start": {"amplitude": 0.6, "duration_s": 0.08, "frequency_hz": 0},
	"boost_stop": {"amplitude": 0.3, "duration_s": 0.05, "frequency_hz": 0},
	"low_hull": {"amplitude": 0.9, "duration_s": 0.3, "frequency_hz": 0},
	"shield_break": {"amplitude": 0.7, "duration_s": 0.06, "frequency_hz": 0},
	"ship_hit": {"amplitude": 0.8, "duration_s": 0.1, "frequency_hz": 0},
	"salvage_pickup": {"amplitude": 0.35, "duration_s": 0.04, "frequency_hz": 250},
	"wall_impact": {"amplitude": 0.5, "duration_s": 0.06, "frequency_hz": 0},
	"wall_impact_min_speed": 2,
	"wall_impact_full_speed": 10
}"""
## Wall normals point back into the tunnel: a wall on the ship's right has a
## normal pointing left (the ship's -x on an unturned ship).
const RIGHT_WALL: Vector3 = Vector3(-1.0, 0.0, 0.0)
const LEFT_WALL: Vector3 = Vector3(1.0, 0.0, 0.0)
## A wall ahead (the ship looks down -z) has a normal pointing back at +z.
const FRONT_WALL: Vector3 = Vector3(0.0, 0.0, 1.0)


static func _wall(normal: Vector3, speed: float, ship: int = 0) -> SimEvent:
	return SimEvent.new(SimEvent.Kind.WALL_IMPACT, ship, speed, normal)


static func _spec() -> HapticsSpec:
	return HapticsSpec.parse_json(VALID)


## Feeds `events` through a combat wiring using the VALID file and returns the
## requests as [hand, amplitude] pairs.
static func _feed(events: Array[SimEvent], ship: ShipState = ShipState.new()) -> Array:
	var combat: CombatWiring = CombatWiring.new()
	combat.hit_haptics.spec = _spec()
	var requests: Array = []
	combat.hit_haptics.request_hook = func(hand: String, pulse: Dictionary) -> void:
		requests.append([hand, snappedf(pulse["amplitude"], 0.0001)])
	combat.feed_events(events, ship, false)
	return requests


static func _expect_error(text: String, field: String) -> String:
	var spec: HapticsSpec = HapticsSpec.parse_json(text)
	if spec.error == "":
		return "text without a valid %s was accepted" % field
	if not spec.error.contains("\"%s\"" % field):
		return "error '%s' does not name %s" % [spec.error, field]
	return ""


func test_the_shipped_file_has_the_starting_wall_values() -> String:
	var spec: HapticsSpec = HapticsSpec.load_file()
	if spec.error != "":
		return spec.error
	var pulse: Dictionary = spec.pulse_for(HapticsSpec.WALL_IMPACT)
	if pulse != {"amplitude": 0.5, "duration_s": 0.06, "frequency_hz": 0.0}:
		return "wall_impact is %s" % pulse
	if spec.wall_min_speed != 2.0 or spec.wall_full_speed != 10.0:
		return "speeds are %s..%s" % [spec.wall_min_speed, spec.wall_full_speed]
	return ""


func test_amplitude_scales_from_a_quarter_to_full_and_never_past_one() -> String:
	var spec: HapticsSpec = _spec()
	var cases: Dictionary = {1.99: -1.0, 2.0: 0.125, 6.0: 0.3125, 10.0: 0.5, 25.0: 0.5}
	for speed: float in cases:
		var pulse: Dictionary = spec.wall_pulse(speed)
		var want: float = cases[speed]
		if want < 0.0:
			if not pulse.is_empty():
				return "%s m/s gave %s" % [speed, pulse]
			continue
		if not is_equal_approx(pulse.get("amplitude", -1.0), want):
			return "%s m/s gave amplitude %s, not %s" % [speed, pulse.get("amplitude"), want]
		if pulse["duration_s"] != 0.06:
			return "%s m/s changed the duration: %s" % [speed, pulse]
	var data: Dictionary = JSON.parse_string(VALID)
	data["wall_impact"]["amplitude"] = 1.0
	var loud: HapticsSpec = HapticsSpec.parse_json(JSON.stringify(data))
	if loud.wall_pulse(40.0)["amplitude"] > 1.0:
		return "the amplitude went past 1"
	if not spec.wall_pulse(NAN).is_empty():
		return "a NaN speed pulsed"
	return ""


func test_a_right_wall_at_6_m_per_s_pulses_the_right_hand_scaled() -> String:
	var requests: Array = _feed([_wall(RIGHT_WALL, 6.0)] as Array[SimEvent])
	if requests != [["right", 0.3125]]:
		return "a right wall at 6 m/s gave %s" % [requests]
	requests = _feed([_wall(LEFT_WALL, 6.0)] as Array[SimEvent])
	if requests != [["left", 0.3125]]:
		return "a left wall at 6 m/s gave %s" % [requests]
	return ""


func test_the_side_is_read_in_the_ship_frame() -> String:
	# Turned 90 degrees left, the ship's right faces world -z: a wall there has a +z normal.
	var ship: ShipState = ShipState.new()
	ship.orientation = Basis(Vector3.UP, PI / 2.0)
	var requests: Array = _feed([_wall(Vector3(0.0, 0.0, 1.0), 10.0)] as Array[SimEvent], ship)
	if requests != [["right", 0.5]]:
		return "a turned ship's right wall gave %s" % [requests]
	return ""


func test_a_hit_below_the_minimum_pulses_nothing() -> String:
	var requests: Array = _feed([_wall(RIGHT_WALL, 1.5)] as Array[SimEvent])
	return "" if requests.is_empty() else "a 1.5 m/s scrape gave %s" % [requests]


func test_a_corner_hit_pulses_once_with_the_strongest() -> String:
	var requests: Array = _feed([_wall(LEFT_WALL, 3.0), _wall(RIGHT_WALL, 8.0),
		_wall(FRONT_WALL, 4.0)] as Array[SimEvent])
	if requests != [["right", snappedf(0.40625, 0.0001)]]:
		return "a corner hit gave %s" % [requests]
	return ""


func test_a_front_wall_pulses_both_hands() -> String:
	var requests: Array = _feed([_wall(FRONT_WALL, 10.0)] as Array[SimEvent])
	if requests != [["left", 0.5], ["right", 0.5]]:
		return "a front wall gave %s" % [requests]
	return ""


func test_another_ship_pulses_nothing() -> String:
	var requests: Array = _feed([_wall(RIGHT_WALL, 10.0, 1)] as Array[SimEvent])
	return "" if requests.is_empty() else "ship 1's wall gave %s" % [requests]


func test_left_handed_mode_does_not_swap_the_side() -> String:
	# The side comes from the wall alone: no mapping is consulted, as for shots.
	if HitHaptics.hands_for(HitFlash.side_for(RIGHT_WALL, Basis.IDENTITY)) != ["right"]:
		return "a right wall maps to %s" % [HitHaptics.hands_for(HitFlash.side_for(RIGHT_WALL, Basis.IDENTITY))]
	return ""


func test_flat_runs_call_the_hook_and_send_nothing() -> String:
	var haptics: HitHaptics = HitHaptics.new(_spec())
	var hand: XRController3D = XRController3D.new()
	haptics.right_controller = hand
	var requests: Array = []
	haptics.request_hook = func(side: String, pulse: Dictionary) -> void: requests.append(side)
	haptics.wall(HitFlash.RIGHT, 10.0, false)
	hand.free()
	if requests != ["right"]:
		return "the hook saw %s" % [requests]
	requests.clear()
	HitHaptics.new(null).wall(HitFlash.RIGHT, 10.0, false)
	return "" if requests.is_empty() else "no spec still asked for a pulse"


func test_missing_and_bad_wall_fields_are_rejected_naming_them() -> String:
	for key: String in ["wall_impact", "wall_impact_min_speed", "wall_impact_full_speed"]:
		var data: Dictionary = JSON.parse_string(VALID)
		data.erase(key)
		var failure: String = _expect_error(JSON.stringify(data), key)
		if failure != "":
			return failure
	for key: String in HapticsSpec.NUMBER_RANGES:
		var low: float = HapticsSpec.NUMBER_RANGES[key][0]
		var high: float = HapticsSpec.NUMBER_RANGES[key][1]
		for bad: Variant in [low - 0.001, high + 0.001, true, "3"]:
			var data: Dictionary = JSON.parse_string(VALID)
			data[key] = bad
			var failure: String = _expect_error(JSON.stringify(data), key)
			if failure != "":
				return "%s = %s: %s" % [key, bad, failure]
	var data: Dictionary = JSON.parse_string(VALID)
	data["wall_impact_full_speed"] = 2
	return _expect_error(JSON.stringify(data), "wall_impact_full_speed")


func test_wall_pulses_leave_the_ship_alone() -> String:
	var ship: ShipState = ShipState.new()
	var before: int = ship.state_hash()
	_feed([_wall(RIGHT_WALL, 10.0), _wall(FRONT_WALL, 5.0)] as Array[SimEvent], ship)
	return "" if ship.state_hash() == before else "feeding wall events changed the ship"
