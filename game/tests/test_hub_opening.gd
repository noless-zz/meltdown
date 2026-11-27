extends RefCounted

## `HubOpening`, split from `HubWiring` (#1448, CRW-2): the hub's model is built
## on the run's profile and stored fitting, and the helpers keep their answers.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const PROFILE_PATH: String = "user://t1448_profile.json"
const FITTING_PATH: String = "user://t1448_fitting.json"


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


func _run() -> RunWiring:
	_clean()
	var run: RunWiring = RunWiring.new(12345, ProfileStore.new(PROFILE_PATH),
		func() -> int: return 77, THREE_LEVELS, false)
	run.ship.fittings = FittingStore.new(FITTING_PATH)
	return run


func test_model_for_reads_the_runs_profile_and_fitting() -> String:
	var run: RunWiring = _run()
	var config: HubConfig = HubConfig.load_shipped()
	if config.error != "":
		_clean()
		return "the shipped hub file is rejected: %s" % config.error
	var model: HubModel = HubOpening.model_for(run, config, ComponentList.COMPONENTS_DIR)
	var result: String = ""
	if model.profile != run.profile:
		result = "the model is not on the run's profile"
	elif model.fitting == null:
		result = "the model has no fitting"
	elif model.ship_data.is_empty():
		result = "the model has no ship data"
	_clean()
	return result


func test_waiting_save_is_null_without_a_store_or_a_save() -> String:
	if HubOpening.waiting_save(null) != null:
		return "a missing store offers a save"
	if HubOpening.waiting_save(RunSaveStore.new("user://t1448_no_run_save.json")) != null:
		return "an empty store offers a save"
	return ""


func test_ship_data_at_a_missing_path_is_empty() -> String:
	if not HubOpening.ship_data_at("res://no_such_ship_1448.json").is_empty():
		return "a missing ship file gives data"
	return ""
