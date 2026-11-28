extends RefCounted

## Control labels at the home base and the shaft choice (#1469, PLT-5, CRW-2,
## ARC-4, ARC-3): the data file names only what acts there; a bad key names its
## field and leaves no labels; while pointing selects those labels show on the
## hands layer above the fade and the flight ones do not; in flight the flight
## labels are back unchanged; both hand modes; and the label clearance holds.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"
const SHIPPED: Dictionary = {
	"right_stick": "step",
	"right_button_lower": "select / launch",
	"left_menu": "tap: menu",
}


static func _rig(left_handed: bool) -> Node:
	var rig: Node = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.call("build")
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = left_handed
	rig.set("mapping", mapping)
	return rig


## Hangs a shown shaft panel under `rig`, as `ShaftChoiceWiring` does when it opens.
static func _open_shaft_choice(rig: Node) -> ShaftPanel:
	var panel: ShaftPanel = ShaftPanel.new()
	rig.add_child(panel)
	panel.visible = true
	return panel


## Both hands' labels, keyed as `ControlLabels.for_layout` keys them.
static func _shown(rig: Node) -> Dictionary:
	var result: Dictionary = {}
	for hand: String in ["left", "right"]:
		var texts: Dictionary = (rig.call("model_for", hand) as ControllerModel).label_texts()
		for control: String in texts:
			result[hand + "_" + control] = texts[control]
	return result


## The first label or leader of `rig` not drawn as `at_base` says, or "".
static func _layer_problem(rig: Node, at_base: bool) -> String:
	for hand: String in ["left", "right"]:
		var set: ControlLabelSet = (rig.call("model_for", hand) as ControllerModel).label_set()
		for child: Node in set.get_children():
			var drawn: VisualInstance3D = child as VisualInstance3D
			if drawn == null:
				continue
			var on_hands: bool = (drawn.layers & HubRoom.HANDS_LAYER_BIT) != 0
			if on_hands != at_base:
				return "%s %s on the hands layer: %s" % [hand, child.name, on_hands]
			var label: Label3D = child as Label3D
			var wanted: int = ControlLabelSet.BASE_RENDER_PRIORITY if at_base else 0
			if label != null and label.render_priority != wanted:
				return "%s %s priority %d, want %d" % [hand, child.name, label.render_priority, wanted]
	return ""


func test_shipped_file_names_only_what_acts_there() -> String:
	var loaded: BaseLabels = BaseLabels.load_file()
	if loaded.error != "":
		return loaded.error
	if loaded.labels != SHIPPED:
		return "labels %s" % [loaded.labels]
	if loaded.mirror_left_handed:
		return "the base reads the right stick and A in both hand modes"
	for text: String in loaded.labels.values():
		for flight_word: String in ["fire", "boost", "nose", "strafe"]:
			if text.contains(flight_word):
				return "flight word in %s" % text
	return ""


func test_bad_key_names_its_field_and_leaves_no_labels() -> String:
	var cases: Dictionary = {
		"{\"labels\": {\"right_stick\": \"step\"}, \"colour\": 1}": "colour",
		"{\"labels\": {\"right_paddle\": \"step\"}}": "labels.right_paddle",
		"{\"labels\": {\"stick\": \"step\"}}": "labels.stick",
		"{\"labels\": {\"right_stick\": 3}}": "labels.right_stick",
		"{\"labels\": {\"right_stick\": \" \"}}": "labels.right_stick",
		"{\"labels\": {}, \"mirror_left_handed\": 1}": "mirror_left_handed",
		"{\"labels\": []}": "labels",
		"{\"mirror_left_handed\": true}": "labels",
		"[1]": "object",
		"{": "invalid JSON",
	}
	for text: String in cases:
		var parsed: BaseLabels = BaseLabels.parse_json(text)
		if not parsed.error.contains(str(cases[text])):
			return "%s: error \"%s\" does not name %s" % [text, parsed.error, cases[text]]
		if not parsed.labels.is_empty() or not parsed.for_hand_mode(true).is_empty():
			return "%s: kept labels %s" % [text, parsed.labels]
	if BaseLabels.load_file("res://xr/no_such_labels.json").error == "":
		return "a missing file was accepted"
	return ""


func test_hand_modes() -> String:
	var shipped: BaseLabels = BaseLabels.load_file()
	if shipped.for_hand_mode(false) != SHIPPED or shipped.for_hand_mode(true) != SHIPPED:
		return "the shipped labels moved: %s" % [shipped.for_hand_mode(true)]
	shipped.mirror_left_handed = true
	var mirrored: Dictionary = {
		"left_stick": "step",
		"left_button_lower": "select / launch",
		"left_menu": "tap: menu",
	}
	if shipped.for_hand_mode(true) != mirrored:
		return "mirrored %s" % [shipped.for_hand_mode(true)]
	if shipped.for_hand_mode(false) != SHIPPED:
		return "right-handed moved when mirrored: %s" % [shipped.for_hand_mode(false)]
	return ""


func test_shaft_choice_shows_base_labels_and_flight_returns() -> String:
	for left_handed: bool in [false, true]:
		var rig: Node = _rig(left_handed)
		var flight: Dictionary = _shown(rig)
		var mapping: ThumbstickMapping = rig.get("mapping")
		var want_flight: Dictionary = ControlLabels.for_mapping(mapping)
		var message: String = ""
		if flight != want_flight:
			message = "flight before %s" % [flight]
		elif _layer_problem(rig, false) != "":
			message = "flight before: " + _layer_problem(rig, false)
		var panel: ShaftPanel = _open_shaft_choice(rig)
		rig.call("refresh_labels")
		if message == "" and _shown(rig) != BaseLabels.load_file().for_hand_mode(left_handed):
			message = "shaft choice %s" % [_shown(rig)]
		elif message == "" and _layer_problem(rig, true) != "":
			message = "shaft choice: " + _layer_problem(rig, true)
		panel.visible = false
		rig.call("refresh_labels")
		if message == "" and _shown(rig) != flight:
			message = "flight after %s" % [_shown(rig)]
		elif message == "" and _layer_problem(rig, false) != "":
			message = "flight after: " + _layer_problem(rig, false)
		rig.free()
		if message != "":
			return "left-handed %s: %s" % [left_handed, message]
	return ""


func test_rig_notices_the_place_each_frame() -> String:
	var rig: Node = _rig(false)
	var panel: ShaftPanel = _open_shaft_choice(rig)
	rig.call("_process", 0.0)
	var message: String = ""
	if not bool(rig.call("base_labels_shown")):
		message = "the open panel was not noticed"
	panel.visible = false
	rig.call("_process", 0.0)
	if message == "" and bool(rig.call("base_labels_shown")):
		message = "the closed panel was not noticed"
	rig.free()
	return message


func test_home_base_stations_show_base_labels() -> String:
	var rig: Node = _rig(false)
	var room: HubRoom = HubRoom.new()
	rig.add_child(room)
	var stations: HubStations = HubStations.new(room)
	rig.add_child(stations)
	room.show_for(rig.get_node("Camera") as Camera3D)  # As the hub shows it (#1508).
	stations.visible = true
	rig.call("refresh_labels")
	var message: String = ""
	if _shown(rig) != SHIPPED:
		message = "base %s" % [_shown(rig)]
	elif _layer_problem(rig, true) != "":
		message = _layer_problem(rig, true)
	rig.free()
	return message


func test_refused_file_leaves_no_labels_at_the_base() -> String:
	var rig: Node = _rig(false)
	rig.set("base_labels", BaseLabels.parse_json("{\"labels\": {\"right_paddle\": \"x\"}}"))
	_open_shaft_choice(rig)
	rig.call("refresh_labels")
	var shown: Dictionary = _shown(rig)
	rig.free()
	return "" if shown.is_empty() else "showed %s" % [shown]


func test_base_labels_are_clear() -> String:
	for left_handed: bool in [false, true]:
		for quest3: bool in [false, true]:
			var rig: Node = _rig(left_handed)
			_open_shaft_choice(rig)
			rig.call("refresh_labels")
			if quest3:
				for hand: String in ["left", "right"]:
					(rig.call("model_for", hand) as ControllerModel).on_vendor_model_loaded()
			var shown: int = _shown(rig).size()
			var message: String = ControlLabelClearance.check(rig)
			rig.free()
			if shown != SHIPPED.size():
				return "left-handed %s, quest3 %s: %d labels" % [left_handed, quest3, shown]
			if message != "":
				return "left-handed %s, quest3 %s: %s" % [left_handed, quest3, message]
	return ""
