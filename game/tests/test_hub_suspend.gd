extends RefCounted

## The hub after a suspend (#1107, RUN-8, CMF-8, MP-2): the suspend's restart
## opens the hub with the resume row; resuming takes the save once and names
## the run's level 2 for the fade to fly; a save that will not load is
## discarded with the hub left open; a launch scraps the waiting run and flies
## a new run's first level.

const RUN_SEED: int = 12345
const OTHER_SEED: int = 4242
const SAVE_PATH: String = "user://t1107_hub_run.json"


func _clean() -> void:
	for each: String in [SAVE_PATH, SafeFileWrite.temp_path(SAVE_PATH)]:
		if FileAccess.file_exists(each):
			DirAccess.remove_absolute(each)


## A level start whose run of `RUN_SEED` was suspended at its first choice and
## whose hub opened on it, as the suspend's restart opens it.
func _opened(hub: HubWiring) -> LevelStart:
	_clean()
	var level_start: LevelStart = LevelStart.new()
	level_start.run = RunWiring.new(RUN_SEED, null, func() -> int: return OTHER_SEED)
	level_start.run.saves = RunSaveStore.new(SAVE_PATH)
	level_start.source = level_start.run.level_source()
	level_start.run.escape_for_choice({}, 0)
	level_start.run.suspend()
	hub.open_after(level_start, null)
	return level_start


func _done(hub: HubWiring) -> void:
	if hub.panel != null:
		hub.panel.free()
	_clean()


func test_the_suspend_opens_the_hub_with_the_resume_row() -> String:
	var hub: HubWiring = HubWiring.new()
	var level_start: LevelStart = _opened(hub)
	var result: String = ""
	if not hub.is_open() or level_start.run.suspended:
		result = "after the suspend: hub open %s, still flagged %s" % [hub.is_open(), level_start.run.suspended]
	elif not hub.text.model.run_waits() or hub.text.model.waiting() != {"level": 2, "seed": RUN_SEED}:
		result = "the hub offers %s" % hub.text.model.waiting()
	_done(hub)
	return result


func test_resume_takes_the_save_and_names_level_two() -> String:
	var hub: HubWiring = HubWiring.new()
	var level_start: LevelStart = _opened(hub)
	var resumed: bool = hub.resume_run()
	var left: bool = level_start.run.saves.has_save()
	var result: String = ""
	if not resumed or hub.is_open() or left:
		result = "resume: answered %s, hub open %s, save left %s" % [resumed, hub.is_open(), left]
	elif level_start.source != level_start.run.level_source() or level_start.run.state.current_depth() != 2 \
			or level_start.run.state.plan.run_seed != RUN_SEED:
		result = "the resume flies %s at depth %d" % [level_start.source, level_start.run.state.current_depth()]
	_done(hub)
	return result


func test_a_save_that_will_not_load_is_discarded_and_the_hub_stays() -> String:
	var hub: HubWiring = HubWiring.new()
	var level_start: LevelStart = _opened(hub)
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ not a run")
	file.close()
	var source: String = level_start.source
	var resumed: bool = hub.resume_run()
	var result: String = ""
	if resumed or not hub.is_open() or FileAccess.file_exists(SAVE_PATH):
		result = "a broken save: answered %s, hub open %s, file left %s" % [resumed, hub.is_open(),
			FileAccess.file_exists(SAVE_PATH)]
	elif hub.text.model.run_waits() or level_start.source != source:
		result = "the hub still offers the broken save or moved the level"
	_done(hub)
	return result


func test_a_launch_scraps_the_waiting_run() -> String:
	var hub: HubWiring = HubWiring.new()
	var level_start: LevelStart = _opened(hub)
	hub.launch()
	var left: bool = level_start.run.saves.has_save()
	var result: String = ""
	if left or hub.is_open():
		result = "after the launch: save left %s, hub open %s" % [left, hub.is_open()]
	elif not level_start.run.active() or level_start.run.state.plan.run_seed != OTHER_SEED \
			or level_start.run.state.level_index != 0 or level_start.source != level_start.run.level_source():
		result = "the launch flies %s, not the new run's first level" % level_start.source
	_done(hub)
	return result
