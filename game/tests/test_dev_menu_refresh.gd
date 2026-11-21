extends RefCounted

## The dev menu's Refresh entry (#852, PRF-1, CMF-1, CMF-4, ARC-3): left /
## right step 90 Hz and 120 Hz and wrap, the texts come from the file, A
## saves the choice and asks the headset for the right rate at once on
## preset 4 and on preset 1, the "(preset 4 only)" note follows the active
## preset, and the entry opens on the option in use, a launch switch's too.

const FakeRuntime := preload("res://tests/fake_refresh_runtime.gd")
const SCRATCH_DIR: String = "user://test_dev_menu_refresh"
const FRAME: float = 1.0 / 72.0
const OFFERED: Array = [72.0, 80.0, 90.0, 120.0]


static func _scratch(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var path: String = SCRATCH_DIR + "/" + name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


static func _tap(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


static func _select(model: DevMenuModel, kind: String) -> void:
	while model.kind() != kind:
		_tap(model, DevMenuModel.DOWN)


static func _comfort(number: int) -> ComfortWiring:
	var comfort: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	comfort.set_preset(number)
	return comfort


## A menu wiring on `comfort` whose refresh rate runs on a fake headset with
## `choice` in use and saves to `path`. Returns [wiring, runtime].
static func _wiring(comfort: ComfortWiring, choice: RefreshChoice, path: String) -> Array:
	var rate: RefreshRate = RefreshRate.new()
	rate.choice = choice
	var runtime: RefCounted = FakeRuntime.new(OFFERED, 90.0)
	rate.begin(runtime, comfort.preset)
	var wiring: DevMenuWiring = DevMenuWiring.new(null, ThumbstickMapping.new(), comfort, null, rate)
	wiring.refresh.path = path
	wiring.attach(null, null, null, Callable(), null, null)
	return [wiring, runtime]


static func _open(wiring: DevMenuWiring, at: float) -> float:
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), at)
	wiring.read(_values(), at + 0.2)
	return at + 0.4


## Walks the open menu to the Refresh entry, pushes right once and confirms with A.
static func _step_and_apply(wiring: DevMenuWiring, at: float) -> float:
	var now: float = at
	var down: Dictionary = _values()
	down["right_stick"] = Vector2(0.0, -1.0)
	while wiring.menu.model.kind() != DevMenuSpec.KIND_REFRESH:
		wiring.read(down, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	var right: Dictionary = _values()
	right["right_stick"] = Vector2(1.0, 0.0)
	for values: Dictionary in [right, _values({"right_button_lower": true})]:
		wiring.read(values, now)
		wiring.read(_values(), now + FRAME)
		now += 0.1
	return now


static func _refresh_line(menu: DevMenu) -> String:
	for line: String in menu.texts():
		if line.contains("Refresh"):
			return line.trim_prefix("> ")
	return ""


static func _saved(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func test_left_and_right_step_and_wrap_and_confirm_returns_the_rate() -> String:
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	model.open("centre", "")
	model.set_refresh(false, true)
	_select(model, DevMenuSpec.KIND_REFRESH)
	var seen: Array[String] = [model.refresh_text()]
	for action: String in [DevMenuModel.RIGHT, DevMenuModel.RIGHT, DevMenuModel.LEFT]:
		_tap(model, action)
		seen.append(model.refresh_text())
	if seen != ["90 Hz", "120 Hz", "90 Hz", "120 Hz"]:
		return "right, right, left showed %s" % [seen]
	var confirmed: String = _tap(model, DevMenuModel.CONFIRM)
	if confirmed != "refresh:120":
		return "confirming 120 Hz returned \"%s\"" % confirmed
	_tap(model, DevMenuModel.LEFT)
	confirmed = _tap(model, DevMenuModel.CONFIRM)
	return "" if confirmed == "refresh:90" else "confirming 90 Hz returned \"%s\"" % confirmed


func test_the_entry_and_its_texts_come_from_the_file() -> String:
	var shipped: DevMenuSpec = DevMenuSpec.load_file()
	var labels: Array[String] = []
	for entry: Dictionary in shipped.entries:
		if entry["kind"] == DevMenuSpec.KIND_REFRESH:
			labels.append(str(entry["label"]))
	if shipped.error != "" or labels != ["Refresh"]:
		return "the shipped file gave Refresh labels %s (%s)" % [labels, shipped.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DevMenuSpec.DEFAULT_FILE))
	data["refresh_90_text"] = "normal"
	data["refresh_120_text"] = "fast"
	data["refresh_note_text"] = "[4 only]"
	var spec: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if spec.error != "":
		return "the edited file was rejected: %s" % spec.error
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.model.set_refresh(true, false)
	menu.open("centre", "")
	var line: String = _refresh_line(menu)
	menu.free()
	if line != "Refresh: < fast [4 only] >":
		return "the entry read \"%s\"" % line
	data["refresh_note_text"] = ""
	var blank: DevMenuSpec = DevMenuSpec.parse(JSON.stringify(data))
	if not blank.error.contains("refresh_note_text"):
		return "a blank note gave \"%s\"" % blank.error
	var fallback: DevMenuSpec = DevMenuSpec.fallback()
	return "" if fallback.entries.any(func(entry: Dictionary) -> bool: return entry["kind"] == "refresh") \
		else "the built-in menu has no Refresh entry"


func test_choosing_on_preset_4_saves_and_asks_for_the_rate_at_once() -> String:
	var path: String = _scratch("preset4.json")
	var made: Array = _wiring(_comfort(4), RefreshChoice.new(), path)
	var wiring: DevMenuWiring = made[0]
	var runtime: RefCounted = made[1]
	var now: float = _step_and_apply(wiring, _open(wiring, 10.0))
	var problem: String = ""
	if runtime.requests.back() != 120.0:
		problem = "choosing 120 Hz on preset 4 asked for %s" % [runtime.requests]
	elif _saved(path) != JSON.stringify({RefreshChoice.FIELD_120_HZ: true}):
		problem = "120 Hz was saved as \"%s\"" % _saved(path)
	elif not wiring.is_open():
		problem = "the menu closed after a Refresh choice"
	if problem == "":
		_step_and_apply(wiring, now)
		var own: float = RefreshRate.target_hz(ComfortPresetFiles.load_number(4))
		if runtime.requests.back() != own:
			problem = "choosing 90 Hz on preset 4 asked for %s, expected %s" % [runtime.requests, own]
		elif _saved(path) != JSON.stringify({RefreshChoice.FIELD_120_HZ: false}):
			problem = "90 Hz was saved as \"%s\"" % _saved(path)
	var reloaded: RefreshChoice = RefreshChoice.new()
	reloaded.use_saved(path)
	if problem == "" and (reloaded.on or reloaded.source != RefreshChoice.SOURCE_SAVED):
		problem = "the next start read on %s from %s" % [reloaded.on, reloaded.source]
	wiring.menu.free()
	return problem


func test_on_preset_1_the_choice_is_saved_but_the_preset_keeps_its_rate() -> String:
	var path: String = _scratch("preset1.json")
	var made: Array = _wiring(_comfort(1), RefreshChoice.new(), path)
	var wiring: DevMenuWiring = made[0]
	var runtime: RefCounted = made[1]
	_open(wiring, 10.0)
	var before: String = _refresh_line(wiring.menu)
	_step_and_apply(wiring, 11.0)
	var after: String = _refresh_line(wiring.menu)
	var own: float = RefreshRate.target_hz(ComfortPresetFiles.load_number(1))
	var problem: String = ""
	if before != "Refresh: < 90 Hz (preset 4 only) >" or after != "Refresh: < 120 Hz (preset 4 only) >":
		problem = "on preset 1 the entry read \"%s\" then \"%s\"" % [before, after]
	elif runtime.requests.back() != own or runtime.requests.has(120.0):
		problem = "choosing 120 Hz on preset 1 asked for %s, expected only %s" % [runtime.requests, own]
	elif _saved(path) != JSON.stringify({RefreshChoice.FIELD_120_HZ: true}):
		problem = "120 Hz on preset 1 was saved as \"%s\"" % _saved(path)
	if problem == "":
		# A Comfort change while the menu is open drops the note at once.
		wiring.comfort.set_preset(4)
		wiring.read(_values(), 12.0)
		if _refresh_line(wiring.menu) != "Refresh: < 120 Hz >":
			problem = "after switching to preset 4 the entry read \"%s\"" % _refresh_line(wiring.menu)
	wiring.menu.free()
	return problem


func test_the_entry_opens_on_the_option_in_use_a_launch_switch_included() -> String:
	var path: String = _scratch("switch.json")
	RefreshChoice.new().save(false, path)
	var switched: RefreshChoice = RefreshChoice.parse(PackedStringArray(["--refresh=120"]), "")
	switched.use_saved(path)
	var made: Array = _wiring(_comfort(4), switched, path)
	var wiring: DevMenuWiring = made[0]
	_open(wiring, 10.0)
	var line: String = _refresh_line(wiring.menu)
	wiring.menu.free()
	if line != "Refresh: < 120 Hz >":
		return "with --refresh=120 over a saved 90 the entry read \"%s\"" % line
	# Before the XR session begins the menu loads the session's choice itself.
	var saved_path: String = _scratch("saved.json")
	RefreshChoice.new().save(true, saved_path)
	var early: DevMenuRefresh = DevMenuRefresh.new(RefreshRate.new(), _comfort(4))
	early.path = saved_path
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	early.show_on(model)
	return "" if model.refresh_high and model.refresh_allowed \
		else "before the session the entry showed 120 Hz %s, allowed %s" % [
			model.refresh_high, model.refresh_allowed]
