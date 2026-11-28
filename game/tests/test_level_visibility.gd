extends RefCounted

## Room-and-portal visibility (#1364, GFX-3, PRF-2): the camera's own box is
## always drawn, a box seen down a straight line of openings is drawn, a box
## behind a solid wall or out of the window the openings leave is hidden, and
## on generated levels nothing hidden can be seen: a brute-force walk of sight
## lines from sample eyes finds every box a line passes through drawn. The
## settings are data with a named-field fallback, and the level view shows
## only the boxes found.

const Levels := preload("res://tests/bot_sweep_levels.gd")
const SEEDS: Array[int] = [11, 4242, 90210]
const G2_FILE: String = "res://data/levels/g2_level.json"
## Sight lines per eye: a grid this many across the window each way.
const RAYS_ACROSS: int = 9
## Sight lines aimed at random points inside each box, per eye.
const TARGETS_PER_BOX: int = 6
const EYES_PER_LEVEL: int = 24

static var _levels: Levels = null


## Room A, a corridor B along +x, room C at its end, and D opening off C's far
## side wall well away from the corridor's line. E lies beside A with a solid
## wall between (no shared volume).
func _rooms() -> BoxUnion:
	var boxes: Array[BoxBounds] = [
		BoxBounds.new(Vector3(0, 0, 0), Vector3(10, 4, 4)),
		BoxBounds.new(Vector3(9, 1, 1), Vector3(21, 3, 3)),
		BoxBounds.new(Vector3(20, 0, -10), Vector3(30, 4, 14)),
		BoxBounds.new(Vector3(25, 1, 13), Vector3(27, 3, 25)),
		BoxBounds.new(Vector3(0, 0, 5), Vector3(10, 4, 9)),
	]
	return BoxUnion.new(boxes)


func _looking(direction: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(direction.normalized().y) < 0.9 else Vector3.BACK
	return Basis.looking_at(direction, up)


func _names(flags: Array[bool]) -> String:
	var names: String = ""
	for index: int in flags.size():
		if flags[index]:
			names += "ABCDE"[index] if flags.size() == 5 else "%d " % index
	return names


func test_the_shipped_settings_read_and_cull() -> String:
	var settings: Dictionary = LevelVisibilitySettings.load_file()
	if settings.has("error"):
		return "shipped visibility settings rejected: %s" % settings["error"]
	if not bool(settings["enabled"]):
		return "culling is off in the shipped settings"
	# Wider than a Quest 3 eye pair (about 104 by 96 degrees) with room to turn.
	if rad_to_deg(2.0 * atan(float(settings["tan_half_width"]))) < 110.0 \
			or rad_to_deg(2.0 * atan(float(settings["tan_half_height"]))) < 100.0:
		return "the view window %s by %s is narrower than the headset's" \
				% [settings["tan_half_width"], settings["tan_half_height"]]
	if float(settings["margin_m"]) < 0.035:
		return "a margin of %s m does not cover each eye's offset from the head" % settings["margin_m"]
	return ""


func test_a_bad_settings_file_names_the_field() -> String:
	var cases: Dictionary = {
		"{\"enabled\": true}": "missing key",
		"[1]": "top level",
		"{\"enabled\": 1, \"tan_half_width\": 1, \"tan_half_height\": 1, \"near_m\": 0.01, \"margin_m\": 0, \"max_steps\": 9}": "\"enabled\"",
		"{\"enabled\": true, \"tan_half_width\": 99, \"tan_half_height\": 1, \"near_m\": 0.01, \"margin_m\": 0, \"max_steps\": 9}": "\"tan_half_width\"",
		"{\"enabled\": true, \"tan_half_width\": 1, \"tan_half_height\": 1, \"near_m\": 0.01, \"margin_m\": 0, \"max_steps\": 9, \"x\": 1}": "unknown key",
	}
	for text: String in cases:
		var parsed: Dictionary = LevelVisibilitySettings.parse(text)
		if not parsed.has("error") or not str(parsed["error"]).contains(cases[text]):
			return "%s gave %s, expected an error naming %s" % [text, parsed, cases[text]]
	var missing: Dictionary = LevelVisibilitySettings.load_file("res://no_such_visibility.json")
	if not missing.has("error") or not str(missing["error"]).contains("no_such_visibility.json"):
		return "a missing file gave %s" % missing
	return ""


func test_the_openings_are_the_shared_volumes() -> String:
	var visibility: LevelVisibility = LevelVisibility.new(_rooms())
	# A-B, B-C, C-D; E only touches nothing.
	if visibility.opening_count() != 3:
		return "%d openings, expected 3" % visibility.opening_count()
	return ""


func test_a_straight_line_of_openings_is_seen() -> String:
	var flags: Array[bool] = LevelVisibility.new(_rooms()).visible(Vector3(2, 2, 2), _looking(Vector3.RIGHT))
	if not (flags[0] and flags[1] and flags[2]):
		return "looking down the corridor drew %s, expected A, B and C" % _names(flags)
	return ""


func test_a_box_out_of_the_window_the_openings_leave_is_hidden() -> String:
	var flags: Array[bool] = LevelVisibility.new(_rooms()).visible(Vector3(2, 2, 2), _looking(Vector3.RIGHT))
	if flags[3]:
		return "D, off C's side wall far from the corridor's line, is drawn: %s" % _names(flags)
	var inside_c: Array[bool] = LevelVisibility.new(_rooms()).visible(Vector3(26, 2, 0), _looking(Vector3.BACK))
	if not inside_c[3]:
		return "D is hidden from inside C looking at its opening: %s" % _names(inside_c)
	return ""


func test_a_box_behind_a_solid_wall_or_behind_the_eye_is_hidden() -> String:
	var visibility: LevelVisibility = LevelVisibility.new(_rooms())
	var toward_e: Array[bool] = visibility.visible(Vector3(5, 2, 2), _looking(Vector3.BACK))
	if toward_e[4] or toward_e[1]:
		return "looking at the solid wall towards E drew %s" % _names(toward_e)
	var away: Array[bool] = visibility.visible(Vector3(5, 2, 2), _looking(Vector3.LEFT))
	if away != [true, false, false, false, false]:
		return "looking away from the corridor drew %s, expected only A" % _names(away)
	return ""


func test_the_own_box_is_drawn_and_switching_off_or_leaving_draws_all() -> String:
	var visibility: LevelVisibility = LevelVisibility.new(_rooms())
	for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.FORWARD]:
		if not visibility.visible(Vector3(15, 2, 2), _looking(direction))[1]:
			return "the corridor is hidden from inside it looking %s" % direction
	var off: Dictionary = LevelVisibility.DEFAULTS.duplicate()
	off["enabled"] = false
	if visibility.visible(Vector3(5, 2, 2), _looking(Vector3.LEFT), off).has(false):
		return "culling switched off still hides a box"
	if visibility.visible(Vector3(50, 50, 50), _looking(Vector3.LEFT)).has(false):
		return "an eye outside every box hides a box"
	var capped: Dictionary = LevelVisibility.DEFAULTS.duplicate()
	capped["max_steps"] = 1
	if visibility.visible(Vector3(2, 2, 2), _looking(Vector3.RIGHT), capped).has(false):
		return "a search past its step cap hides a box"
	return ""


func test_generated_levels_hide_nothing_that_can_be_seen() -> String:
	var settings: Dictionary = LevelVisibility.DEFAULTS.duplicate()
	# No margin: the search itself must be sound for the exact eye.
	settings["margin_m"] = 0.0
	var unions: Array[BoxUnion] = [LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE)).union]
	for level_seed: int in SEEDS:
		unions.append(_generated(level_seed))
	var drawn: int = 0
	var possible: int = 0
	for which: int in unions.size():
		var union: BoxUnion = unions[which]
		if union.boxes.size() < 3:
			return "level %d has %d boxes" % [which, union.boxes.size()]
		var visibility: LevelVisibility = LevelVisibility.new(union)
		var random: RandomNumberGenerator = RandomNumberGenerator.new()
		random.seed = 1364 + which
		for sample: int in EYES_PER_LEVEL:
			var box_index: int = random.randi_range(0, union.boxes.size() - 1)
			var eye: Vector3 = _point_in(union.boxes[box_index], random)
			var direction: Vector3 = Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1),
					random.randf_range(-1, 1))
			if direction.length() < 0.1:
				direction = Vector3.FORWARD
			var basis: Basis = _looking(direction)
			var flags: Array[bool] = visibility.visible(eye, basis, settings)
			if not flags[box_index]:
				return "level %d: the eye's own box %d is hidden" % [which, box_index]
			for seen: int in _seen_by_rays(union, eye, basis, settings, random):
				if not flags[seen]:
					return "level %d: box %d is hidden but a sight line from %s reaches it" % [which, seen, eye]
			drawn += flags.count(true)
			possible += flags.size()
	if drawn >= possible:
		return "culling hid no box from any sample eye"
	return ""


func test_the_level_view_shows_only_the_visible_boxes() -> String:
	var view: LevelView = LevelView.new()
	view.build(_rooms())
	var result: String = ""
	if view.box_count() != 5 or view.box_node(2) == null or view.walls_of(2) == null:
		result = "the view built %d box nodes" % view.box_count()
	view.cull(Vector3(5, 2, 2), _looking(Vector3.LEFT))
	for index: int in view.box_count() if result == "" else 0:
		if view.box_node(index).visible != (index == 0):
			result = "box %d shown %s looking away from the corridor" % [index, view.box_node(index).visible]
	if result == "" and (view.drawn_boxes != 1 or view.drawn_surfaces != view.surfaces_of(0)):
		result = "counted %d boxes and %d surfaces drawn" % [view.drawn_boxes, view.drawn_surfaces]
	view.set_culling(false)
	for index: int in view.box_count() if result == "" else 0:
		if not view.box_node(index).visible:
			result = "box %d stays hidden with culling switched off" % index
	view.free()
	return result


func test_frames_are_drawn_with_the_box_they_sink_into() -> String:
	var union: BoxUnion = _rooms()
	var frames: Array[Dictionary] = LevelFrames.quads(union, 0.6, 0.3)
	if frames.is_empty():
		return "no frames to place"
	for quad: Dictionary in frames:
		var owner: int = LevelViewBoxes.frame_box(union, quad)
		var centre: Vector3 = ((quad["min"] as Vector3) + (quad["max"] as Vector3)) * 0.5
		var box: BoxBounds = union.boxes[owner]
		var grown: AABB = AABB(box.min_corner, box.max_corner - box.min_corner).grow(1e-3)
		if not grown.has_point(centre):
			return "a frame of box %d centred at %s is drawn with box %d, which does not hold it" \
					% [quad["box"], centre, owner]
	return ""


func _generated(level_seed: int) -> BoxUnion:
	if _levels == null:
		_levels = Levels.new()
	return _levels.level_of(_levels.generate(level_seed)).union


## A point at least 0.2 m inside `box` (its centre when it is thinner).
static func _point_in(box: BoxBounds, random: RandomNumberGenerator) -> Vector3:
	var point: Vector3 = Vector3.ZERO
	for axis: int in 3:
		var low: float = box.min_corner[axis] + 0.2
		var high: float = box.max_corner[axis] - 0.2
		point[axis] = random.randf_range(low, high) if high > low else (box.min_corner[axis] + box.max_corner[axis]) * 0.5
	return point


## Every box a sight line passes through before it leaves the union, over a
## grid of lines across the view window. Exact: each box is open along a line
## for an interval, and the line is clear while those intervals join up.
static func _seen_by_rays(union: BoxUnion, eye: Vector3, basis: Basis, settings: Dictionary,
		random: RandomNumberGenerator) -> Array[int]:
	var tw: float = float(settings["tan_half_width"])
	var th: float = float(settings["tan_half_height"])
	var directions: Array[Vector3] = []
	for i: int in RAYS_ACROSS:
		for j: int in RAYS_ACROSS:
			var x: float = lerpf(-tw, tw, (float(i) + 0.5) / RAYS_ACROSS)
			var y: float = lerpf(-th, th, (float(j) + 0.5) / RAYS_ACROSS)
			directions.append(basis * Vector3(x, y, -1.0))
	# Lines aimed into every box too, where a grid would pass between openings.
	for box: BoxBounds in union.boxes:
		for target: int in TARGETS_PER_BOX:
			var local: Vector3 = basis.inverse() * (_point_in(box, random) - eye)
			if local.z < 0.0 and absf(local.x / local.z) <= tw and absf(local.y / local.z) <= th:
				directions.append(basis * local)
	var seen: Array[int] = []
	for direction: Vector3 in directions:
		for index: int in _boxes_along(union, eye, direction):
			if not seen.has(index):
				seen.append(index)
	return seen


static func _boxes_along(union: BoxUnion, eye: Vector3, direction: Vector3) -> Array[int]:
	var spans: Array[Vector3] = []  # (enter, leave, box)
	for index: int in union.boxes.size():
		var box: BoxBounds = union.boxes[index]
		var enter: float = -INF
		var leave: float = INF
		for axis: int in 3:
			if absf(direction[axis]) < 1e-9:
				if eye[axis] <= box.min_corner[axis] or eye[axis] >= box.max_corner[axis]:
					enter = INF
				continue
			var a: float = (box.min_corner[axis] - eye[axis]) / direction[axis]
			var b: float = (box.max_corner[axis] - eye[axis]) / direction[axis]
			enter = maxf(enter, minf(a, b))
			leave = minf(leave, maxf(a, b))
		if leave > enter + 1e-6 and leave > 0.0:
			spans.append(Vector3(enter, leave, index))
	var reach: float = 0.0
	var grew: bool = true
	while grew:
		grew = false
		for span: Vector3 in spans:
			if span.x < reach - 1e-6 and span.y > reach:
				reach = span.y
				grew = true
	var result: Array[int] = []
	for span: Vector3 in spans:
		if span.x < reach - 1e-4 and span.y > 1e-4:
			result.append(int(span.z))
	return result
