extends RefCounted

## The Auto-level menu option (#1247, FLT-1, CMF-1, CMF-2, CMF-5, CMF-6,
## ARC-3): the row and its texts; On (preset) and locked on presets 1 and 2;
## off by default on presets 3, 4 and the custom mode and switched there; the
## choice saved and applied again at start; a held roll never corrected; and a
## release at 90 degrees levelled at no more than the preset file's rate.

const Swivel := preload("res://tests/test_dev_menu_swivel.gd")
const CUSTOM: int = ComfortPresetFiles.CUSTOM_NUMBER
## Bank left after levelling: the rate is truncated to whole milliradians per
## second, which leaves well under a hundredth of a degree.
const LEVEL_DEG: float = 0.01


static func _entry(comfort: ComfortWiring, name: String) -> DevMenuAutoLevel:
	var entry: DevMenuAutoLevel = DevMenuAutoLevel.new(comfort)
	entry.store = AutoLevelChoice.new(Swivel.scratch(name))
	return entry


static func _model() -> DevMenuModel:
	return DevMenuModel.new(DevMenuSpec.load_file(), [] as Array[String])


static func _toggle(model: DevMenuModel) -> DevMenuValueToggle:
	return model.value(DevMenuSpec.KIND_AUTO_LEVEL) as DevMenuValueToggle


## A ship with its nose `elevation_deg` above the horizon, banked by
## `bank_deg` about the nose in the direction a positive roll rate turns.
static func _banked(bank_deg: float, elevation_deg: float = 0.0) -> Basis:
	var pitched: Basis = Basis(Vector3.RIGHT, deg_to_rad(elevation_deg))
	return pitched.rotated(pitched.z.normalized(), deg_to_rad(bank_deg)).orthonormalized()


static func _bank_deg(orientation: Basis) -> float:
	return rad_to_deg(ComfortAutoLevel.bank(orientation))


func test_the_shipped_row_and_texts() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "":
		return "the shipped menu was rejected: %s" % spec.error
	var labels: Array[String] = []
	for entry: Dictionary in spec.entries:
		if entry["kind"] == DevMenuSpec.KIND_AUTO_LEVEL:
			labels.append(str(entry["label"]))
	if labels != ["Auto-level"]:
		return "auto_level rows labelled %s" % str(labels)
	var texts: Array[String] = [spec.auto_level_on_text, spec.auto_level_off_text, spec.auto_level_preset_text]
	if texts != ["On", "Off", "(preset)"]:
		return "the row's texts are %s" % str(texts)
	if AutoLevelChoice.DEFAULT_PATH != "user://meltdown_auto_level.json":
		return "the choice is saved at %s" % AutoLevelChoice.DEFAULT_PATH
	return ""


func test_presets_one_and_two_show_on_preset_and_cannot_switch() -> String:
	var comfort: ComfortWiring = Swivel.new_comfort()
	var entry: DevMenuAutoLevel = _entry(comfort, "fixed.json")
	var path: String = Swivel.SCRATCH_DIR + "/fixed.json"
	var model: DevMenuModel = _model()
	for number: int in [1, 2]:
		comfort.set_preset(number)
		entry.show_on(model)
		if model.value_text(DevMenuSpec.KIND_AUTO_LEVEL) != "On (preset)":
			return "preset %d shows \"%s\"" % [number, model.value_text(DevMenuSpec.KIND_AUTO_LEVEL)]
		_toggle(model).step(1)
		if model.value(DevMenuSpec.KIND_AUTO_LEVEL).confirmed() != "auto_level:on":
			return "preset %d: stepping switched the locked row" % number
		entry.choose("auto_level:off")
		if not comfort.preset.levels_roll():
			return "preset %d stopped levelling after choosing Off" % number
		if FileAccess.file_exists(path):
			return "preset %d: a choice there was saved" % number
	return ""


func test_off_by_default_on_presets_three_four_and_custom() -> String:
	var custom_text: String = "{\"base\": 3, \"display_name\": \"Mine\"}"
	var comfort: ComfortWiring = Swivel.new_comfort(custom_text)
	var entry: DevMenuAutoLevel = _entry(comfort, "default.json")
	entry.start()
	var model: DevMenuModel = _model()
	if ComfortPresetFiles.load_number(3).auto_level:
		return "comfort_pilot.tres still has auto_level on"
	for number: int in [3, 4, CUSTOM]:
		comfort.set_preset(number)
		entry.show_on(model)
		if comfort.preset.levels_roll():
			return "preset %d levels with nothing chosen" % number
		if model.value_text(DevMenuSpec.KIND_AUTO_LEVEL) != "Off" or _toggle(model).locked:
			return "preset %d shows \"%s\"" % [number, model.value_text(DevMenuSpec.KIND_AUTO_LEVEL)]
	return ""


func test_choosing_switches_presets_three_four_and_custom() -> String:
	var custom_text: String = "{\"base\": 4, \"display_name\": \"Mine\"}"
	var comfort: ComfortWiring = Swivel.new_comfort(custom_text)
	var entry: DevMenuAutoLevel = _entry(comfort, "switch.json")
	var model: DevMenuModel = _model()
	for number: int in [3, 4, CUSTOM]:
		comfort.set_preset(number)
		entry.choose("auto_level:on")
		entry.show_on(model)
		if not comfort.preset.levels_roll() or not comfort.filter.preset.levels_roll():
			return "preset %d: On did not level" % number
		if model.value_text(DevMenuSpec.KIND_AUTO_LEVEL) != "On":
			return "preset %d: On shows \"%s\"" % [number, model.value_text(DevMenuSpec.KIND_AUTO_LEVEL)]
		entry.choose("auto_level:off")
		if comfort.preset.levels_roll() or comfort.filter.preset.levels_roll():
			return "preset %d: Off still levels" % number
	comfort.set_preset(4)
	if not comfort.preset.has_no_intervention():
		return "preset 4 with the option off is not free of intervention"
	if not ComfortPresetFiles.load_number(4).has_no_intervention():
		return "the option changed the shared preset 4 file"
	return ""


func test_the_choice_is_saved_and_survives_a_restart() -> String:
	var path: String = Swivel.scratch("restart.json")
	var first: ComfortWiring = Swivel.new_comfort()
	var entry: DevMenuAutoLevel = DevMenuAutoLevel.new(first)
	entry.store = AutoLevelChoice.new(path)
	first.set_preset(4)
	entry.choose("auto_level:on")
	if JSON.parse_string(FileAccess.get_file_as_string(path)) != {"enabled": true}:
		return "the file holds %s" % FileAccess.get_file_as_string(path)
	var second: ComfortWiring = Swivel.new_comfort()
	var restarted: DevMenuAutoLevel = DevMenuAutoLevel.new(second)
	restarted.store = AutoLevelChoice.new(path)
	restarted.start()
	for number: int in [3, 4]:
		second.set_preset(number)
		if not second.preset.levels_roll():
			return "after a restart preset %d does not level" % number
	Swivel.write(path, "{\"enabled\": 1}")
	var bad: AutoLevelChoice = AutoLevelChoice.new(path)
	if bad.load_saved() != AutoLevelChoice.UNSET or bad.warnings.size() != 1 \
			or not bad.warnings[0].contains(path):
		return "a bad file was not warned by path and ignored: %s" % str(bad.warnings)
	return ""


func test_a_held_roll_is_never_corrected() -> String:
	for number: int in [3, 4]:
		var preset: ComfortPreset = AutoLevelChoice.applied(ComfortPresetFiles.load_number(number),
			AutoLevelChoice.ON)
		var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
		var ship: ShipState = ShipState.new()
		ship.orientation = _banked(45.0, 10.0)
		for tick: int in 120:
			var roll: int = [1, -1, 700, -1500][tick % 4]
			var held: ShipInput = ShipInput.new(Vector3i(0, 0, -900), Vector3i(0, 0, roll))
			var out: ShipInput = filter.filter(held, ship.orientation)
			if out.turn_q.z != roll:
				return "preset %d tick %d: roll %d came out as %d" % [number, tick, roll, out.turn_q.z]
			ship.step(Vector3.ZERO, out.turn())
	return ""


func test_released_grips_and_a_dead_zone_stick_count_as_no_roll() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var preset: ComfortPreset = AutoLevelChoice.applied(ComfortPresetFiles.load_number(4),
		AutoLevelChoice.ON)
	var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
	var inside: float = mapping.stick_dead_zone * 0.5
	var mapped: ShipInput = mapping.map_controls(Vector2(inside, inside), Vector2(-inside, inside),
		0.0, 0.0, 0.0, 0.0)
	if mapped.turn_q.z != 0:
		return "released grips and a stick in its dead zone mapped to roll %d" % mapped.turn_q.z
	if filter.filter(mapped, _banked(30.0)).turn_q.z >= 0:
		return "no correction towards level with the roll released"
	var gripped: ShipInput = mapping.map_controls(Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0, 0.05)
	if gripped.turn_q.z == 0 or filter.filter(gripped, _banked(30.0)).turn_q.z != gripped.turn_q.z:
		return "a light grip's roll %d was corrected" % gripped.turn_q.z
	return ""


func test_release_at_90_degrees_levels_within_the_rate_monotonically() -> String:
	for number: int in [3, 4]:
		var preset: ComfortPreset = AutoLevelChoice.applied(ComfortPresetFiles.load_number(number),
			AutoLevelChoice.ON)
		var rate: float = preset.auto_level_rate_deg_per_s
		var allowed: int = ceili(90.0 / rate * ShipState.TICK_RATE) + 1
		for start: float in [90.0, -90.0]:
			var filter: ComfortInputFilter = ComfortInputFilter.new(preset)
			var ship: ShipState = ShipState.new()
			ship.orientation = _banked(start)
			var previous: float = start
			for tick: int in allowed:
				var out: ShipInput = filter.filter(ShipInput.new(), ship.orientation)
				if absi(out.turn_q.z) > ComfortInputFilter.cap_q(rate):
					return "preset %d: roll %d over %s deg/s" % [number, out.turn_q.z, rate]
				ship.step(Vector3.ZERO, out.turn())
				var bank: float = _bank_deg(ship.orientation)
				var rolled: float = absf(previous) - absf(bank)
				if rolled < -0.000001 or rolled > rate / ShipState.TICK_RATE + 0.001 \
						or (signf(bank) == -signf(start) and absf(bank) > LEVEL_DEG):
					return "preset %d from %s: tick %d went from %f to %f" % [number, start, tick,
						previous, bank]
				previous = bank
			if absf(previous) > LEVEL_DEG:
				return "preset %d from %s: still %f after %d ticks" % [number, start, previous, allowed]
	return ""
