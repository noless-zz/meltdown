extends RefCounted

## Nothing else in the mine may read as the reactor (#1208, SLV-3, PLT-2): a
## glowing orange miner beacon near the exit was taken for a second reactor. This
## reads the three look files and fails if a trapped miner's or a fire's main
## colour comes within `MIN_HUE_DEGREES` of the reactor's, or is too grey for
## its hue to show, so a later tweak of the data cannot bring the confusion back
## (ARC-4).

## A sixth of the colour wheel: orange against yellow or red is closer than this
## and read alike in a dark tunnel; orange against green or blue is well past it.
const MIN_HUE_DEGREES: float = 60.0
## Below this saturation a colour reads as white or grey and its hue says little.
const MIN_SATURATION: float = 0.4


static func _hue_distance(a: Color, b: Color) -> float:
	var apart: float = absf(a.h - b.h) * 360.0
	return minf(apart, 360.0 - apart)


static func _reactor_colors() -> Dictionary:
	var look: Dictionary = ReactorLook.parse(FileAccess.get_file_as_string(ReactorLook.DEFAULT_FILE))
	if look.has("error"):
		return look
	return {"core_color": look["core_color"], "light_color": look["light_color"]}


static func _check(label: String, color: Color) -> String:
	if color.s < MIN_SATURATION:
		return "%s %s is too grey (saturation %.2f) for its hue to tell it from the reactor" \
			% [label, color, color.s]
	var reactor: Dictionary = _reactor_colors()
	if reactor.has("error"):
		return "reactor look rejected: %s" % reactor["error"]
	for key: String in reactor:
		var apart: float = _hue_distance(color, reactor[key])
		if apart < MIN_HUE_DEGREES:
			return "%s %s is %.0f degrees of hue from the reactor's %s %s, under %.0f" \
				% [label, color, apart, key, reactor[key], MIN_HUE_DEGREES]
	return ""


func test_the_hue_distance_wraps_round_the_wheel() -> String:
	var red: Color = Color(1.0, 0.0, 0.0)
	if absf(_hue_distance(red, Color(1.0, 0.0, 0.2)) - 11.8) > 0.5:
		return "red to a pinkish red is %.1f degrees" % _hue_distance(red, Color(1.0, 0.0, 0.2))
	if absf(_hue_distance(red, Color(0.0, 1.0, 1.0)) - 180.0) > 0.5:
		return "red to cyan is %.1f degrees" % _hue_distance(red, Color(0.0, 1.0, 1.0))
	return ""


func test_the_old_orange_beacon_would_fail() -> String:
	# The miner beacon of 22 Nov, the colour the owner took for a reactor.
	if _check("old beacon", Color(1.0, 0.62, 0.22)) == "":
		return "the old orange beacon passed; the check would not catch the confusion"
	return ""


func test_a_trapped_miner_is_unlike_the_reactor() -> String:
	var look: Dictionary = MinerView.parse_look(FileAccess.get_file_as_string(MinerView.DEFAULT_LOOK_FILE))
	if look.has("error"):
		return "miner look rejected: %s" % look["error"]
	var message: String = _check("the miner beacon", look["beacon"]["color"])
	if message != "":
		return message
	return _check("the miner ring fill", look["ring"]["fill_color"])


func test_a_fire_is_unlike_the_reactor() -> String:
	var look: Dictionary = DebrisLook.parse(FileAccess.get_file_as_string(DebrisLook.DEFAULT_FILE))
	if look.has("error"):
		return "debris look rejected: %s" % look["error"]
	return _check("the fire", look["fire_color"])


func test_the_built_in_looks_are_unlike_the_reactor_too() -> String:
	# The fallbacks are drawn when a look file is rejected.
	var message: String = _check("the fallback miner beacon", MinerView.FALLBACK_LOOK["beacon"]["color"])
	if message != "":
		return message
	return _check("the fallback fire", DebrisLook.FALLBACK["fire_color"])


func test_a_miner_beacon_and_a_burning_fire_are_not_round() -> String:
	# The reactor core is a sphere; a beacon column and a flame cone are not.
	var miners: MinerView = MinerView.new()
	var beacon: CylinderMesh = miners._beacon_mesh
	var result: String = ""
	if beacon == null or beacon.radial_segments > 8 or beacon.height <= 2.0 * beacon.top_radius:
		result = "the miner beacon is not a tall column: %s" % miners._beacon_mesh
	miners.free()
	if result != "":
		return result
	var debris: DebrisView = DebrisView.new()
	var flame: CylinderMesh = debris._flame_mesh
	if flame == null or flame.top_radius != 0.0:
		result = "the fire flame is not a cone: %s" % debris._flame_mesh
	debris.free()
	return result
