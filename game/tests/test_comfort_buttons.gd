extends RefCounted

## `ComfortButtons` on its own (#1157): the preset button acts once per press,
## the label button flips once per click while the map is elsewhere, and
## `ComfortWiring` answers through it under its old names.


func test_preset_button_acts_once_per_press() -> String:
	var buttons: ComfortButtons = ComfortButtons.new(ThumbstickMapping.new())
	var down: Dictionary = {buttons.preset_button(): true}
	if not buttons.preset_pressed(down):
		return "the first frame of a press did not count"
	if buttons.preset_pressed(down):
		return "holding the button counted twice"
	if buttons.preset_pressed({}):
		return "the release counted"
	if not buttons.preset_pressed(down):
		return "a second press did not count"
	return ""


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


func test_comfort_wiring_switches_preset_through_the_buttons() -> String:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var start: int = comfort.number
	var down: Dictionary = {comfort.preset_button(): true}
	comfort.read_preset_button(down)
	if comfort.number == start:
		return "a press of the preset button kept preset %d" % start
	var after: int = comfort.number
	comfort.read_preset_button(down)
	if comfort.number != after:
		return "holding the preset button switched again"
	return ""
