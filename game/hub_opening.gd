class_name HubOpening
extends RefCounted

## When the hub opens and what it opens on (#1093, #1107, CRW-2, RUN-8), split
## from `HubWiring` (#1448) so the scene wiring keeps only the open hub's frames.
##
## Single levels never open the hub, nor does an escape that leads to a shaft
## choice or the next level: only the end of a run (`ends_run`), or the shaft
## panel's "Suspend run" row. While a suspended run waits in the run's
## `RunSaveStore`, the hub offers to resume it (`waiting_save`); a save that
## does not read back is not offered.
##
## `model_for` reads the run's upgrade tree, ship file, stored fitting and crew
## into the `HubModel` the pages show. Nothing here touches nodes; it reads
## files and the run, and changes neither (MP-2).


## True when `session` has just ended `level_start`'s run: the ship is lost
## or the run's last level is escaped, on the level the run flies now.
static func ends_run(level_start: LevelStart, session: LocalSession) -> bool:
	var flown: RunWiring = level_start.run
	if flown == null or not flown.active() or level_start.source != flown.level_source():
		return false
	if session.sim.outcome() == ExitRule.Outcome.ESCAPED:
		return flown.on_last_level() and not flown.escape_taken
	return session.current_ship().hull <= 0.0


## The run waiting in `saves`, or null when there is none or it does not read
## back; a temporary file left by a killed save is never offered.
static func waiting_save(saves: RunSaveStore) -> RunSave:
	if saves == null or not saves.has_save():
		return null
	var saved: RunSave = RunSave.parse_json(FileAccess.get_file_as_string(saves.path))
	return saved if saved.error == "" else null


## The hub's model on `run`'s profile, crew roles and stored fitting, with the
## hub file's `config` and the components in `components_dir`. The fitting the
## hub changes is the model's `fitting`.
static func model_for(run: RunWiring, config: HubConfig, components_dir: String) -> HubModel:
	var tree: UpgradeTree = UpgradeTree.parse(RunShip.upgrade_texts(run.ship.upgrades_dir))
	var ship_data: Dictionary = ship_data_at(run.ship.ship_path)
	var stored: Fitting = run.ship.fittings.load_fitting() if run.ship.fittings != null else Fitting.new()
	# A stale slot would make every fit fail the check; the run drops it anyway.
	var fitting: Fitting = FittingStore.valid_for(stored, tree, run.profile.crafted, ship_data)
	var roles: CrewRoles = run.roles if run.roles != null else CrewRoles.parse_json("")
	var model: HubModel = HubModel.create(config, run.profile, roles,
		ComponentList.parse(RunShip.upgrade_texts(components_dir)), tree, fitting, ship_data)
	model.parts = HubPartInfo.load_shipped()
	model.set_waiting(waiting_save(run.saves))
	return model


## The ship file at `path` as a dictionary; empty when missing or not an object.
static func ship_data_at(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
