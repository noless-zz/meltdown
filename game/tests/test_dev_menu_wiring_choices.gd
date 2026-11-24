extends RefCounted

## The dev menu's choices through its wiring (#763, PLT-5, DEV-6, ARC-3,
## CMF-8, MP-2): they save the corner, restart on a seed or the same source
## behind a fade, fly a fresh random seed, and take a waiting update. Split
## from `test_dev_menu_wiring.gd` (#1283), whose fixtures these are.

const Wiring := preload("res://tests/test_dev_menu_wiring.gd")
const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"


func test_choices_save_the_corner_and_restart_on_a_seed_or_the_same_source() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Wiring.wired("res://data/levels/g2_level.json", restarts)
	var now: float = 1.0
	Wiring.tap(wiring, now)
	# Corner: right from the opened corner until top_left, then confirm.
	now = Wiring.select(wiring, DevMenuSpec.KIND_CORNER, now + 0.5)
	var right: Dictionary = Wiring.pad_values()
	right["right_stick"] = Vector2(1.0, 0.0)
	while wiring.menu.model.corner() != "top_left":
		Wiring.press(wiring, right, now)
		now += 0.1
	Wiring.confirm(wiring, now)
	var saved: PanelCorner = PanelCorner.new(Wiring.SCRATCH_DIR + "/panel.json")
	saved.load_saved()
	if saved.corner() != "top_left" or PanelCorner.current != "top_left" or not wiring.is_open():
		Wiring.done(wiring)
		return "corner saved as %s, current %s, menu open %s" % [saved.corner(), PanelCorner.current, wiring.is_open()]
	PanelCorner.current = PanelCorner.CENTRE
	# Level: step to the seed choice, then the right trigger up to 40 and B up to 42.
	now = Wiring.select(wiring, DevMenuSpec.KIND_LEVEL, now + 0.5)
	while wiring.menu.model.levels.choice() != DevMenuLevels.CHOICE_SEED:
		Wiring.press(wiring, right, now)
		now += 0.1
	var far: Dictionary = Wiring.pad_values()
	far["right_trigger"] = 1.0
	for step: int in 4:
		Wiring.press(wiring, far, now)
		now += 0.1
	for step: int in 2:
		Wiring.press(wiring, Wiring.pad_values({"right_button_upper": true}), now)
		now += 0.1
	Wiring.confirm(wiring, now)
	var darkest: float = Wiring.wait(wiring, now + 0.1, DevMenuWiring.FADE_SECONDS * 3.0)
	var after_seed: Array[String] = restarts.duplicate()
	var faded_in: bool = wiring.alpha == 0.0
	# Restart: open again and restart the same source.
	now += 2.0
	Wiring.tap(wiring, now)
	now = Wiring.select(wiring, DevMenuSpec.KIND_RESTART, now + 0.5)
	Wiring.confirm(wiring, now)
	Wiring.wait(wiring, now + 0.1, DevMenuWiring.FADE_SECONDS * 3.0)
	Wiring.done(wiring)
	if after_seed != ["seed:42"] or wiring.is_open():
		return "the seed choice restarted %s, menu open %s" % [after_seed, wiring.is_open()]
	if darkest < 1.0 or not faded_in:
		return "the restart was not behind a fade (darkest %.2f, cleared %s)" % [darkest, faded_in]
	if restarts != ["seed:42", "seed:42"]:
		return "restart flew %s" % [restarts]
	return ""


func test_random_flies_a_fresh_seed() -> String:
	var restarts: Array[String] = []
	var wiring: DevMenuWiring = Wiring.wired("", restarts)
	wiring.pick_seed = func() -> int: return 77
	wiring.apply("level:random")
	Wiring.wait(wiring, 1.0, DevMenuWiring.FADE_SECONDS * 3.0)
	Wiring.done(wiring)
	return "" if restarts == ["seed:77"] else "random flew %s" % [restarts]


## An update wiring whose start-up check, from a fake transport, offers a newer build.
static func _update_wiring() -> UpdateWiring:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = true
	var running: BuildInfo = BuildInfo.new()
	running.commit = OTHER_COMMIT
	var fake: FakeUpdateTransport = FakeUpdateTransport.new()
	fake.body = FileAccess.get_file_as_string(FIXTURE)
	var update: UpdateWiring = UpdateWiring.new()
	update.attach_with(null, UpdateRequest.new(settings, fake, running, true))
	return update


func test_a_waiting_update_is_an_entry_that_starts_it_and_none_without() -> String:
	var restarts: Array[String] = []
	var plain: DevMenuWiring = Wiring.wired("", restarts, UpdateWiring.new())
	Wiring.tap(plain, 1.0)
	var plain_lines: Array[String] = plain.menu.texts()
	Wiring.done(plain)
	for line: String in plain_lines:
		if line.contains("Update"):
			return "an update entry shows without a waiting build: %s" % [plain_lines]
	var update: UpdateWiring = _update_wiring()
	var version: String = update.waiting_version()
	var chosen: Array[Dictionary] = []
	update.update_chosen.connect(func(result: Dictionary) -> void: chosen.append(result))
	var wiring: DevMenuWiring = Wiring.wired("", restarts, update)
	Wiring.tap(wiring, 1.0)
	var lines: Array[String] = wiring.menu.texts()
	# On the top list after the section rows, above Close (#1301).
	var listed: bool = version != "" and lines.find("Update to %s" % version) == lines.size() - 2 \
		and lines[lines.size() - 1] == "Close"
	Wiring.confirm(wiring, DevMenuWalk.select_wired(wiring, DevMenuSpec.KIND_UPDATE, 1.5))
	var open: bool = wiring.is_open()
	Wiring.done(wiring)
	update.notice.free()
	if not listed:
		return "the waiting build %s is not the entry above Close: %s" % [version, lines]
	if chosen.size() != 1 or open or not restarts.is_empty():
		return "choosing the entry started %d updates, menu open %s, restarts %s" % [chosen.size(), open, restarts]
	return ""
