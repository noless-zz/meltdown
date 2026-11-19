extends RefCounted

## Control labels fade while flying (issue #147, PLT-5, CMF-4, ARC-3): the
## data file and its range checks, the timing of the fade, the 25 degree rule
## for "near the centre of view", and the rig fading each hand on its own.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
## One headset frame at 90 Hz.
const FRAME_S: float = 1.0 / 90.0


func _valid_data() -> Dictionary:
	return {"hide_after_s": 5.0, "away_angle_deg": 25.0, "fade_s": 0.5}


## Runs `fade` for `seconds` of frames with the hand at `angle_deg`; returns the last alpha.
static func _fly(fade: LabelFade, seconds: float, angle_deg: float) -> float:
	var alpha: float = fade.alpha()
	var frames: int = roundi(seconds / FRAME_S)
	for i: int in frames:
		alpha = fade.advance(FRAME_S, angle_deg)
	return alpha


## A point `degrees` to the right of the view axis of `view`, 0.5 m away.
static func _point_at(view: Transform3D, degrees: float) -> Vector3:
	var direction: Vector3 = (-view.basis.z).rotated(view.basis.y, -deg_to_rad(degrees))
	return view.origin + direction.normalized() * 0.5


func test_data_file_loads_with_the_issue_values() -> String:
	var fade: LabelFade = LabelFade.load_file()
	if fade.error != "":
		return fade.error
	if not is_equal_approx(fade.hide_after_s, 5.0) or not is_equal_approx(fade.away_angle_deg, 25.0):
		return "shipped file should hide after 5 s beyond 25 degrees, got %s s and %s degrees" % [
			fade.hide_after_s, fade.away_angle_deg]
	return ""


func test_data_file_is_range_checked() -> String:
	var cases: Array[Array] = [
		["hide_after_s", 0.1, "within"],
		["hide_after_s", 120.0, "within"],
		["away_angle_deg", 2.0, "within"],
		["away_angle_deg", 100.0, "within"],
		["fade_s", 0.0, "within"],
		["fade_s", true, "must be a number"],
		["extra", 1.0, "unknown key"],
	]
	for case: Array in cases:
		var data: Dictionary = _valid_data()
		data[case[0]] = case[1]
		var fade: LabelFade = LabelFade.parse_json(JSON.stringify(data))
		if not (str(case[2]) in fade.error):
			return "%s = %s should be rejected with '%s', got '%s'" % [case[0], case[1], case[2], fade.error]
	var missing: Dictionary = _valid_data()
	missing.erase("fade_s")
	if not ("missing key" in LabelFade.parse_json(JSON.stringify(missing)).error):
		return "a missing key should be rejected"
	if LabelFade.parse_json(JSON.stringify(_valid_data())).error != "":
		return "valid data rejected"
	if LabelFade.load_file("res://xr/no_such_file.json").error == "":
		return "a missing file should be rejected"
	return ""


func test_labels_stay_while_the_hand_is_near_the_centre() -> String:
	var fade: LabelFade = LabelFade.parse_json(JSON.stringify(_valid_data()))
	var alpha: float = _fly(fade, 60.0, 10.0)
	if not is_equal_approx(alpha, 1.0):
		return "labels faded to %f with the hand 10 degrees off the view axis" % alpha
	return ""


func test_labels_fade_after_five_seconds_away() -> String:
	var fade: LabelFade = LabelFade.parse_json(JSON.stringify(_valid_data()))
	var alpha: float = _fly(fade, 4.9, 40.0)
	if not is_equal_approx(alpha, 1.0):
		return "labels started fading before 5 s away: %f at 4.9 s" % alpha
	alpha = _fly(fade, 0.35, 40.0)
	if not (alpha > 0.0 and alpha < 1.0):
		return "labels should be part way through the fade at 5.25 s, got %f" % alpha
	alpha = _fly(fade, 0.5, 40.0)
	if not is_zero_approx(alpha):
		return "labels should be gone 0.5 s into the fade, got %f" % alpha
	return ""


func test_labels_fade_back_when_the_hand_comes_near() -> String:
	var fade: LabelFade = LabelFade.parse_json(JSON.stringify(_valid_data()))
	_fly(fade, 10.0, 40.0)
	var alpha: float = _fly(fade, 0.25, 5.0)
	if not (alpha > 0.0 and alpha < 1.0):
		return "labels should be fading in after 0.25 s near, got %f" % alpha
	alpha = _fly(fade, 0.3, 5.0)
	if not is_equal_approx(alpha, 1.0):
		return "labels should be back after 0.55 s near, got %f" % alpha
	return ""


func test_a_glance_restarts_the_five_seconds() -> String:
	var fade: LabelFade = LabelFade.parse_json(JSON.stringify(_valid_data()))
	_fly(fade, 4.0, 40.0)
	_fly(fade, 0.1, 5.0)
	var alpha: float = _fly(fade, 4.0, 40.0)
	if not is_equal_approx(alpha, 1.0):
		return "a look at the hand should restart the 5 s, got %f after 4 s more away" % alpha
	return ""


func test_twenty_five_degrees_off_the_view_axis_is_the_limit() -> String:
	var fade: LabelFade = LabelFade.parse_json(JSON.stringify(_valid_data()))
	# A turned and raised head, so the rule follows the view and not the world.
	var view: Transform3D = Transform3D(Basis.from_euler(Vector3(0.3, 1.1, 0.0)), Vector3(0.2, 1.6, -0.4))
	var near: float = LabelFade.angle_off_view(view, _point_at(view, 24.0))
	var away: float = LabelFade.angle_off_view(view, _point_at(view, 26.0))
	if absf(near - 24.0) > 0.01 or absf(away - 26.0) > 0.01:
		return "angles measured %f and %f, want 24 and 26" % [near, away]
	if not fade.is_near_centre(near) or fade.is_near_centre(away):
		return "24 degrees should be near and 26 away"
	var straight: float = LabelFade.angle_off_view(view, view.origin - view.basis.z)
	if not is_zero_approx(straight):
		return "a point on the view axis measured %f degrees" % straight
	return ""


func test_rig_fades_each_hand_on_its_own() -> String:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	var rig: Node = scene.instantiate()
	rig.call("build")
	var left: ControllerModel = rig.call("model_for", "left") as ControllerModel
	var right: ControllerModel = rig.call("model_for", "right") as ControllerModel
	var view: Transform3D = Transform3D.IDENTITY
	# Hands low and to the sides, about 45 degrees off the view axis.
	var away: Dictionary = {"left": Vector3(-0.3, -0.3, -0.4), "right": Vector3(0.3, -0.3, -0.4)}
	var message: String = ""
	for i: int in roundi(6.0 / FRAME_S):
		rig.call("fade_labels", FRAME_S, view, away)
	if not (is_zero_approx(left.label_alpha()) and is_zero_approx(right.label_alpha())):
		message = "labels should be gone after 6 s away: %f / %f" % [left.label_alpha(), right.label_alpha()]
	var right_up: Dictionary = {"left": away["left"], "right": Vector3(0.05, -0.05, -0.4)}
	for i: int in roundi(1.0 / FRAME_S):
		rig.call("fade_labels", FRAME_S, view, right_up)
	if message == "" and not (is_equal_approx(right.label_alpha(), 1.0) and is_zero_approx(left.label_alpha())):
		message = "only the right hand's labels should come back: left %f, right %f" % [
			left.label_alpha(), right.label_alpha()]
	var label: Label3D = right.label_set().label_for("stick")
	if message == "" and (label == null or not is_equal_approx(label.modulate.a, 1.0)):
		message = "the right stick label is not drawn at full opacity"
	label = left.label_set().label_for("stick")
	if message == "" and (label == null or not is_zero_approx(label.modulate.a)):
		message = "the left stick label should be transparent"
	rig.free()
	return message


func test_show_labels_still_hides_faded_in_labels() -> String:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	var rig: Node = scene.instantiate()
	rig.call("build")
	var near: Dictionary = {"left": Vector3(-0.05, 0.0, -0.4), "right": Vector3(0.05, 0.0, -0.4)}
	rig.call("fade_labels", FRAME_S, Transform3D.IDENTITY, near)
	rig.set("show_labels", false)
	var message: String = ""
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		if model.labels_visible():
			message = "%s labels visible with show_labels off" % hand
		elif not is_equal_approx(model.label_alpha(), 1.0):
			message = "%s labels lost their fade state" % hand
	rig.free()
	return message
