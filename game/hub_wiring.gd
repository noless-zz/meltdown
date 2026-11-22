class_name HubWiring
extends RefCounted

## The hub between runs (#1093, CRW-2, CRF-3, CRF-4, RUN-1, RUN-7). When a run
## ends, lost or won, the end screen's restart press opens the hub panel
## instead of flying the next run at once: the run is moved on first, exactly
## as the press always moved it (`RunWiring.after_session` banks, adds crew and
## picks the next run's seed), and the hub shows the run's own profile, so what
## was just banked can be crafted at once. "Drop into the mine" saves the
## profile and fitting and answers the restart that flies the new run's first
## level, through the end screen's fade (CMF-8); the level is built after the
## save, so `RunShip` reads the fitting the pilot just chose. A launch the
## fitting check refuses shows its reason on the panel and stays in the hub.
##
## Single levels never open it, nor does an escape that leads to a shaft
## choice or the next level: only the end of a run. A `--run` launch still
## starts straight into a run, so the acceptance suites and replays fly as
## before.
##
## While it is open it takes the controls as the dev menu does (decision
## record 0009): the frame's values reach the rest of `main.gd` idle, so the
## ship gets neutral input, and the right stick and A drive the panel through
## the dev menu's named actions. Every craft and fit is saved when it happens,
## so a killed app keeps it. The hub changes only the profile and fitting it
## was handed (MP-2) and reads no comfort setting (ARC-3). It sits beside
## `main.gd` because it reads `RunWiring` and the `net/` session's outcome.

const LOG_PREFIX: String = "[meltdown run]"

## Under the rig origin once `attach` has run; made unattached by `open_for` in tests.
var panel: HubPanel = null
## The open hub's text; null while closed.
var text: HubText = null
## The run the hub launches; kept after closing.
var run: RunWiring = null
## The fitting the hub changes, saved through `run.ship.fittings`.
var fitting: Fitting = null
## Where component files are read; tests may point it elsewhere.
var components_dir: String = ComponentList.COMPONENTS_DIR

var _actions: Dictionary = {}


## Hangs the panel under `rig`. Calling it again adds nothing.
func attach(rig: Node3D) -> void:
	if panel != null or rig == null:
		return
	panel = HubPanel.new()
	rig.add_child(panel)


func is_open() -> bool:
	return text != null


## True when `session` has just ended `level_start`'s run: the ship is lost
## or the run's last level is escaped, on the level the run flies now.
static func ends_run(level_start: LevelStart, session: LocalSession) -> bool:
	var flown: RunWiring = level_start.run
	if flown == null or not flown.active() or level_start.source != flown.level_source():
		return false
	if session.sim.outcome() == ExitRule.Outcome.ESCAPED:
		return flown.on_last_level() and not flown.escape_taken
	return session.current_ship().hull <= 0.0


## Called on the end screen's restart press. When `session` ended the run,
## moves the run on, opens the hub and returns true; the caller then waits for
## `update` instead of restarting. False, changing nothing, otherwise, and also
## when the hub's data cannot be read, so the next run flies at once as before.
func open_after(level_start: LevelStart, session: LocalSession) -> bool:
	if not ends_run(level_start, session):
		return false
	var config: HubConfig = HubConfig.load_shipped()
	if config.error != "":
		print("%s the hub cannot open, flying the next run: %s" % [LOG_PREFIX, config.error])
		return false
	level_start.source = level_start.run.after_session(session)
	return open_for(level_start.run, config)


## Opens the hub on `p_run`'s profile, crew roles and fitting, with the hub
## file's `config` (the shipped one when not given). False, with a logged
## line, when the hub file is rejected.
func open_for(p_run: RunWiring, config: HubConfig = null) -> bool:
	if config == null:
		config = HubConfig.load_shipped()
	if config.error != "":
		print("%s the hub cannot open: %s" % [LOG_PREFIX, config.error])
		return false
	run = p_run
	var tree: UpgradeTree = UpgradeTree.parse(RunShip.upgrade_texts(run.ship.upgrades_dir))
	var ship_data: Dictionary = _ship_data(run.ship.ship_path)
	var stored: Fitting = run.ship.fittings.load_fitting() if run.ship.fittings != null else Fitting.new()
	# A stale slot would make every fit fail the check; the run drops it anyway.
	fitting = FittingStore.valid_for(stored, tree, run.profile.crafted, ship_data)
	var roles: CrewRoles = run.roles if run.roles != null else CrewRoles.parse_json("")
	text = HubText.new(HubModel.create(config, run.profile, roles,
		ComponentList.parse(RunShip.upgrade_texts(components_dir)), tree, fitting, ship_data))
	if panel == null:
		panel = HubPanel.new()
	panel.open(text)
	_actions = {}
	print("%s the hub opens" % LOG_PREFIX)
	return true


## Once per frame, after the dev menu and the shaft panel, with the sampled
## `values`. Returns them unchanged while closed, idle but for the menu button while open.
func read(values: Dictionary) -> Dictionary:
	if not is_open():
		return values
	_actions = DevMenuWiring.actions(values)
	return DevMenuWiring.neutral(values)


## Once per frame while open, with the panel's place `head_point`. Returns
## true on the frame a launch passes: the profile and fitting are saved, the
## panel is closed and the caller flies the run's current level. The panel
## holds still while the session is paused.
func update(paused: bool, head_point: Transform3D) -> bool:
	if not is_open():
		return false
	panel.transform = head_point
	if paused or _actions.is_empty():  # No frame read since opening: nothing pressed yet.
		return false
	var result: Dictionary = panel.update(_actions)
	if result.is_empty() or str(result["reason"]) != "":
		return false
	match str((result["pressed"] as Dictionary).get("action", "")):
		HubText.ACTION_CRAFT:
			save_profile()
		HubText.ACTION_FIT:
			save_fitting()
		HubText.ACTION_LAUNCH:
			save_profile()
			save_fitting()
			close()
			print("%s launching from the hub" % LOG_PREFIX)
			return true
	return false


## The fade's opacity: dark while the hub is open.
func alpha() -> float:
	return 1.0 if is_open() else 0.0


func close() -> void:
	text = null
	_actions = {}
	if panel != null:
		panel.close()


## Saves the run's profile; a failure is logged and the hub stays usable.
func save_profile() -> void:
	if run != null and run.store != null and not run.store.save(run.profile):
		print("%s the profile was not saved: %s" % [LOG_PREFIX, run.store.message])


## Saves the hub's fitting; a failure is logged and the hub stays usable.
func save_fitting() -> void:
	var store: FittingStore = run.ship.fittings if run != null else null
	if store != null and fitting != null and not store.save(fitting):
		print("%s the fitting was not saved: %s" % [LOG_PREFIX, store.message])


static func _ship_data(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) \
		if FileAccess.file_exists(path) else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
