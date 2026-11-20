extends RefCounted

## The hit cue on every preset (#618; CMB-2, CMF-1, CMF-8, PLT-6): the side a
## shot came from, one cue per hit, the bar that flashes, the pulses and the
## data files.

const FRAME: float = 1.0 / 90.0
## Shots fly opposite to where they came from: a shot from the right flies left.
const FROM_RIGHT: Vector3 = Vector3.LEFT
const VALID: String = """{
	"edge_seconds": 0.25,
	"edge_color": [1.0, 0.25, 0.15],
	"edge_alpha": 0.55,
	"edge_inset_m": 0.055,
	"edge_width_m": 0.07,
	"bar_seconds": 0.35,
	"bar_color": [1.0, 1.0, 1.0]
}"""


static func _hit(flight: Vector3, ship: int = 0, damage: float = 6.0) -> SimEvent:
	return SimEvent.new(SimEvent.Kind.SHIP_HIT, ship, damage, flight)


static func _with(key: String, value: Variant) -> String:
	var data: Dictionary = JSON.parse_string(VALID)
	if value == null:
		data.erase(key)
	else:
		data[key] = value
	return JSON.stringify(data)


func test_the_side_comes_from_the_hit_direction_in_the_ship_frame() -> String:
	# [direction of flight, expected side]; the ship faces -Z, as the camera does.
	var cases: Array = [
		[Vector3.LEFT, HitFlash.RIGHT], [Vector3.RIGHT, HitFlash.LEFT],
		[Vector3.DOWN, HitFlash.TOP], [Vector3.UP, HitFlash.BOTTOM],
		[Vector3.BACK, HitFlash.FRONT],  # Straight ahead: flies towards +Z, at the ship.
		[Vector3.FORWARD, HitFlash.FRONT],  # Straight behind: no edge points there.
		[Vector3(-0.4, 0.0, -1.0), HitFlash.RIGHT],  # From behind and to the right.
		[Vector3(0.0, 0.5, -1.0), HitFlash.BOTTOM],  # From behind and below.
		[Vector3(-0.5, 0.0, 1.0), HitFlash.FRONT],  # Ahead and a little right.
		[Vector3(-1.0, 0.3, 0.5), HitFlash.RIGHT],
		[Vector3.ZERO, HitFlash.FRONT],
	]
	for case: Array in cases:
		var side: String = HitFlash.side_for(case[0], Basis.IDENTITY)
		if side != case[1]:
			return "a shot flying %s read as %s, not %s" % [case[0], side, case[1]]
	# Turned half round, the world's left-flying shot now comes from the ship's left.
	var turned: Basis = Basis(Vector3.UP, PI)
	if HitFlash.side_for(FROM_RIGHT, turned) != HitFlash.LEFT:
		return "the side ignored the ship's heading: %s" % HitFlash.side_for(FROM_RIGHT, turned)
	# Rolled onto its right side, a shot from above in the world hits the ship's right.
	var rolled: Basis = Basis(Vector3.FORWARD, -PI * 0.5)
	if HitFlash.side_for(Vector3.DOWN, rolled) != HitFlash.RIGHT:
		return "the side ignored the ship's roll: %s" % HitFlash.side_for(Vector3.DOWN, rolled)
	if HitFlash.side_for(FROM_RIGHT, Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)) == "":
		return "a degenerate ship basis gave no side"
	return ""


func test_one_cue_per_hit_and_only_for_hits_on_this_ship() -> String:
	var flash: HitFlash = HitFlash.parse_json(VALID)
	var events: Array[SimEvent] = [
		_hit(FROM_RIGHT), _hit(Vector3.RIGHT, 1),
		SimEvent.new(SimEvent.Kind.WALL_IMPACT, 0, 20.0, Vector3.LEFT),
		SimEvent.new(SimEvent.Kind.ROBOT_HIT, 0, 6.0, Vector3.LEFT),
		null, _hit(Vector3.DOWN),
	]
	var sides: Array[String] = flash.feed(events, 0, Basis.IDENTITY, 40.0, 100.0)
	if sides != ([HitFlash.RIGHT, HitFlash.TOP] as Array[String]):
		return "two hits on ship 0 gave %s" % [sides]
	if flash.side != HitFlash.TOP or not is_equal_approx(flash.edge_opacity(), flash.edge_alpha):
		return "the latest hit does not show at full opacity: %s %f" % [flash.side, flash.edge_opacity()]
	if not flash.feed([] as Array[SimEvent], 0, Basis.IDENTITY, 40.0, 100.0).is_empty():
		return "no events still gave a cue"
	flash.advance(flash.edge_seconds * 0.5)
	if not is_equal_approx(flash.edge_opacity(), flash.edge_alpha * 0.5):
		return "the edge did not fade linearly: %f" % flash.edge_opacity()
	flash.advance(flash.edge_seconds)
	if flash.edge_opacity() != 0.0 or flash.bar_amount(HitFlash.SHIELD) != 0.0:
		return "the flash outlasted its time"
	return ""


func test_the_bar_that_flashes_is_the_one_the_hit_took() -> String:
	var flash: HitFlash = HitFlash.parse_json(VALID)
	flash.feed([] as Array[SimEvent], 0, Basis.IDENTITY, 40.0, 100.0)
	flash.feed([_hit(FROM_RIGHT)] as Array[SimEvent], 0, Basis.IDENTITY, 34.0, 100.0)
	if flash.bar_amount(HitFlash.SHIELD) != 1.0 or flash.bar_amount(HitFlash.HULL) != 0.0:
		return "a hit on the shield flashed shield %f hull %f" % [
			flash.bar_amount(HitFlash.SHIELD), flash.bar_amount(HitFlash.HULL)]
	flash.advance(1.0)
	flash.feed([_hit(FROM_RIGHT)] as Array[SimEvent], 0, Basis.IDENTITY, 0.0, 90.0)
	if flash.bar_amount(HitFlash.SHIELD) != 1.0 or flash.bar_amount(HitFlash.HULL) != 1.0:
		return "a hit through the last of the shield did not flash both"
	flash.advance(1.0)
	flash.feed([_hit(FROM_RIGHT)] as Array[SimEvent], 0, Basis.IDENTITY, 0.0, 84.0)
	if flash.bar_amount(HitFlash.SHIELD) != 0.0 or flash.bar_amount(HitFlash.HULL) != 1.0:
		return "a hit on the bare hull flashed shield %f hull %f" % [
			flash.bar_amount(HitFlash.SHIELD), flash.bar_amount(HitFlash.HULL)]
	# The first feed has nothing to compare with: the shield's if it is up.
	var fresh: HitFlash = HitFlash.parse_json(VALID)
	fresh.feed([_hit(FROM_RIGHT)] as Array[SimEvent], 0, Basis.IDENTITY, 10.0, 100.0)
	if fresh.bar_amount(HitFlash.SHIELD) != 1.0 or fresh.bar_amount(HitFlash.HULL) != 0.0:
		return "a first hit with the shield up did not flash the shield alone"
	fresh = HitFlash.parse_json(VALID)
	fresh.feed([_hit(FROM_RIGHT)] as Array[SimEvent], 0, Basis.IDENTITY, 0.0, 100.0)
	if fresh.bar_amount(HitFlash.HULL) != 1.0:
		return "a first hit with no shield did not flash the hull"
	return ""


func test_the_shipped_file_parses() -> String:
	var flash: HitFlash = HitFlash.load_file()
	if flash.error != "":
		return "shipped file rejected: %s" % flash.error
	if not flash.edge_alpha > 0.0 or flash.edge_color.a != 1.0:
		return "the shipped edge shows nothing"
	var parsed: HitFlash = HitFlash.parse_json(VALID)
	if parsed.error != "" or parsed.edge_color != Color(1.0, 0.25, 0.15) or parsed.bar_seconds != 0.35:
		return "the valid text gave %s %s %f" % [parsed.error, parsed.edge_color, parsed.bar_seconds]
	return ""


func test_bad_files_are_rejected_naming_the_field() -> String:
	var cases: Array = [
		[_with("edge_seconds", null), "edge_seconds"],
		[_with("edge_alpha", 1.5), "edge_alpha"],
		[_with("bar_seconds", true), "bar_seconds"],
		[_with("edge_color", [1.0, 0.0]), "edge_color"],
		[_with("bar_color", [1.0, 2.0, 0.0]), "bar_color"],
		[_with("bar_color", "white"), "bar_color"],
		[_with("glow", 1), "glow"],
	]
	for case: Array in cases:
		var flash: HitFlash = HitFlash.parse_json(case[0])
		if flash.error == "" or not flash.error.contains("\"%s\"" % case[1]):
			return "text with a bad %s gave '%s'" % [case[1], flash.error]
	if HitFlash.parse_json("[1]").error == "" or HitFlash.parse_json("{").error == "":
		return "not an object was accepted"
	if HitFlash.load_file("res://xr/no_such_file.json").error == "":
		return "a missing file was accepted"
	if CombatWiring.load_hit_flash("res://xr/no_such_file.json") != null:
		return "a rejected file still gave a flash"
	return ""


func test_the_overlay_lights_the_side_and_front_lights_all() -> String:
	var overlay: HitFlashOverlay = HitFlashOverlay.new(HitFlash.parse_json(VALID))
	var message: String = ""
	if not overlay.lit_sides().is_empty():
		message = "a new overlay shows %s" % [overlay.lit_sides()]
	overlay.show_flash(HitFlash.LEFT, 0.5, Color.RED)
	if message == "" and overlay.lit_sides() != ([HitFlash.LEFT] as Array[String]):
		message = "a hit from the left lit %s" % [overlay.lit_sides()]
	overlay.show_flash(HitFlash.FRONT, 0.5, Color.RED)
	if message == "" and overlay.lit_sides().size() != 4:
		message = "a hit from the front lit %s" % [overlay.lit_sides()]
	overlay.show_flash(HitFlash.TOP, 0.0, Color.RED)
	if message == "" and not overlay.lit_sides().is_empty():
		message = "opacity 0 still lit %s" % [overlay.lit_sides()]
	# The strips sit at the edges, never across the middle of the view.
	for strip: Node in overlay.get_children():
		var at: Vector3 = (strip as Node3D).position
		if message == "" and maxf(absf(at.x), absf(at.y)) < 0.05:
			message = "%s sits near the view's centre: %s" % [strip.name, at]
	overlay.free()
	return message


func test_the_hand_follows_the_side_and_a_pickup_pulses_both_differently() -> String:
	var haptics: HitHaptics = HitHaptics.new(HapticsSpec.load_file())
	var requests: Array = []
	haptics.request_hook = func(hand: String, pulse: Dictionary) -> void: requests.append([hand, pulse])
	var expected: Dictionary = {
		HitFlash.LEFT: ["left"], HitFlash.RIGHT: ["right"], HitFlash.FRONT: ["left", "right"],
		HitFlash.TOP: ["left", "right"], HitFlash.BOTTOM: ["left", "right"],
	}
	for side: String in expected:
		requests.clear()
		haptics.hit(side, false)
		var hands: Array = requests.map(func(request: Array) -> String: return request[0])
		if hands != expected[side]:
			return "a hit from %s pulsed %s" % [side, hands]
	var hit_pulse: Dictionary = requests[0][1]
	requests.clear()
	haptics.pickup(false)
	if requests.size() != 2 or requests[0][1] == hit_pulse:
		return "a pickup gave %s, the hit %s" % [requests, hit_pulse]
	requests.clear()
	HitHaptics.new(null).hit(HitFlash.LEFT, false)
	return "" if requests.is_empty() else "no spec still asked for a pulse"


func test_combat_wiring_cues_each_hit_and_each_pickup_on_the_local_ship() -> String:
	var combat: CombatWiring = CombatWiring.new()
	var requests: Array[String] = []
	combat.hit_haptics.request_hook = func(hand: String, pulse: Dictionary) -> void:
		requests.append("%s %s" % [hand, pulse["duration_s"]])
	var ship: ShipState = ShipState.new()
	var events: Array[SimEvent] = [
		_hit(FROM_RIGHT), _hit(FROM_RIGHT, 1),
		SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, 0, 0.0, Vector3.ZERO),
		SimEvent.new(SimEvent.Kind.SALVAGE_COLLECTED, 1, 0.0, Vector3.ZERO),
	]
	combat.feed_events(events, ship, false)
	var spec: HapticsSpec = HapticsSpec.load_file()
	var hit_s: float = spec.pulse_for(HapticsSpec.SHIP_HIT)["duration_s"]
	var pickup_s: float = spec.pulse_for(HapticsSpec.SALVAGE_PICKUP)["duration_s"]
	var want: Array[String] = ["right %s" % hit_s, "left %s" % pickup_s, "right %s" % pickup_s]
	if requests != want:
		return "the pulses were %s, not %s" % [requests, want]
	if combat.hit_flash.side != HitFlash.RIGHT:
		return "the flash shows %s" % combat.hit_flash.side
	return ""
