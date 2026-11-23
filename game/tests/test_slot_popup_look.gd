extends RefCounted

## The slot popup's data file and look (#1263, ARC-4, PLT-5): the shipped file
## loads, each bad field is rejected by name, the popup shows the three
## choices and the cancel hint, and it sits above the stick of the hand that
## chooses, mirrored for the left hand.


static func _shipped_text() -> String:
	return FileAccess.get_file_as_string(SlotPopupLook.DEFAULT_FILE)


static func _text_with(key: String, value: Variant) -> String:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data[key] = value
	return JSON.stringify(data)


static func _text_without(key: String) -> String:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data.erase(key)
	return JSON.stringify(data)


func test_shipped_file_loads() -> String:
	var look: Dictionary = SlotPopupLook.parse(_shipped_text())
	if look.has("error"):
		return "shipped slot_popup.json rejected: %s" % look["error"]
	if look["left_text"] != "Replace left gun" or look["right_text"] != "Replace right gun" \
			or look["down_text"] != "Dump":
		return "the shipped choices read %s, %s, %s" % [look["left_text"], look["right_text"], look["down_text"]]
	return ""


func test_every_key_is_required() -> String:
	for key: String in SlotPopupLook.keys():
		var look: Dictionary = SlotPopupLook.parse(_text_without(key))
		if not str(look.get("error", "")).contains(key):
			return "a file without %s was not rejected by name: %s" % [key, look]
	return ""


func test_bad_values_are_rejected_by_name() -> String:
	var bad: Array = [
		["left_text", ""], ["down_text", 3], ["choice_color", [1.0, 0.5]],
		["cancel_color", [2.0, 0.0, 0.0]], ["height_m", 0.5], ["spread_m", "far"],
		["choice_font", 20.5], ["pixel_size", true], ["flick_threshold", 0.1],
		["rest_threshold", 0.0], ["surprise", 1],
	]
	for pair: Array in bad:
		var look: Dictionary = SlotPopupLook.parse(_text_with(pair[0], pair[1]))
		if not str(look.get("error", "")).contains(str(pair[0])):
			return "%s = %s was not rejected by name: %s" % [pair[0], pair[1], look]
	return ""


func test_a_rest_at_or_above_the_flick_is_rejected() -> String:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data["flick_threshold"] = 0.6
	data["rest_threshold"] = 0.6
	var look: Dictionary = SlotPopupLook.parse(JSON.stringify(data))
	return "" if str(look.get("error", "")).contains("rest_threshold") else "a rest equal to the flick was accepted"


func test_a_missing_file_falls_back_with_the_error() -> String:
	var look: Dictionary = SlotPopupLook.load_file("res://xr/no_such_slot_popup.json")
	if not look.has("error") or look["down_text"] != SlotPopupLook.FALLBACK["down_text"]:
		return "a missing file did not give the fallback look with an error"
	return ""


func test_the_popup_shows_the_three_choices_and_starts_hidden() -> String:
	var popup: SlotPopup = SlotPopup.new()
	var problem: String = ""
	if popup.look_error() != "":
		problem = "the shipped look was rejected: %s" % popup.look_error()
	elif popup.visible:
		problem = "the popup shows before it is opened"
	elif popup.left_label.text != "Replace left gun" or popup.right_label.text != "Replace right gun" \
			or popup.down_label.text != "Dump":
		problem = "the labels read %s, %s, %s" % [popup.left_label.text, popup.right_label.text, popup.down_label.text]
	elif not (popup.left_label.position.x < 0.0 and popup.right_label.position.x > 0.0
			and popup.down_label.position.y < 0.0):
		problem = "the choices are not left, right and down of the centre"
	if problem == "":
		popup.show_open(true, null)
		if not popup.visible:
			problem = "show_open(true) left it hidden"
		popup.show_open(false, null)
		if problem == "" and popup.visible:
			problem = "show_open(false) left it showing"
	popup.free()
	return problem


func test_it_sits_above_the_stick_and_mirrors_for_the_left_hand() -> String:
	var anchors: ControllerAnchors = ControllerAnchors.load_file()
	if anchors.error != "":
		return "controller anchors rejected: %s" % anchors.error
	var look: Dictionary = SlotPopupLook.load_file()
	var stick: Vector3 = anchors.table_points("")["stick_click"]
	var right: Vector3 = SlotPopup.place_for(anchors, "right", look)
	var left: Vector3 = SlotPopup.place_for(anchors, "left", look)
	if not right.is_equal_approx(stick + Vector3(0.0, float(look["height_m"]), 0.0)):
		return "right hand: %s, not %s above the stick at %s" % [right, look["height_m"], stick]
	if not left.is_equal_approx(Vector3(-right.x, right.y, right.z)):
		return "the left hand's place %s is not the right's %s mirrored" % [left, right]
	if right.y <= stick.y:
		return "the popup is not above the stick"
	return ""
