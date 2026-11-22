extends RefCounted

## `ComfortButtons` on its own (#1157): the label button flips once per click
## while the map is elsewhere. It holds no preset button any more: X was retired
## (decision record 0011, #1260; see `test_x_button_free.gd`).


func test_label_button_flips_on_the_press_when_the_map_is_elsewhere() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.layout["show_map"] = {"left_button_upper": 1.0}
	var buttons: ComfortButtons = ComfortButtons.new(mapping)
	if buttons.label_button_shows_map() or buttons.shared_click_hold() != null:
		return "a ClickHold was shared though the map is on another control"
	var down: Dictionary = {buttons.label_button(): true}
	if not buttons.read_label_button(down):
		return "the press did not flip the labels"
	if buttons.read_label_button(down):
		return "holding the label button flipped them again"
	return ""


func test_label_button_shares_its_click_hold_with_the_map() -> String:
	var buttons: ComfortButtons = ComfortButtons.new(ThumbstickMapping.new())
	if not buttons.label_button_shows_map():
		return "the default layout no longer puts the map on the label button"
	if buttons.shared_click_hold() != buttons.click_hold:
		return "the shared ClickHold is not the buttons' own"
	return ""


func test_there_is_no_preset_button_any_more() -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	for method: String in ["preset_button", "preset_pressed", "read_preset_button"]:
		if comfort.has_method(method):
			return "ComfortWiring still has %s" % method
	if ThumbstickMapping.new().has_method("preset_button"):
		return "ThumbstickMapping still has preset_button"
	return ""
