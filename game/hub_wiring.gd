class_name HubWiring
extends RefCounted

## The hub between runs (#1093, CRW-2, CRF-3, CRF-4, RUN-1, RUN-7). When a run
## ends, lost or won, the end screen's restart press opens the hub instead of
## flying the next run: the run is moved on first (`RunWiring.after_session`
## banks, adds crew and picks the next seed), so what was just banked can be
## crafted at once. Launching saves the profile and fitting, then answers the
## restart through the end screen's fade (CMF-8); the level is built after the
## save, so `RunShip` reads the fitting just chosen. A refused launch shows its
## reason and stays in the hub.
##
## Single levels never open it, nor does an escape that leads to a shaft
## choice or the next level: only the end of a run, or the shaft panel's
## "Suspend run" row (#1107, RUN-8). While a suspended run waits in the run's
## `RunSaveStore`, the hub offers to resume it: the save is taken (so it resumes
## once only), the run rebuilt and its next level flown through the same fade.
## A save that will not resume is discarded, logged, and the hub stays open. A launch
## discards a waiting save; a `--run` launch starts straight into a run, as replays fly.
##
## While open it takes the controls as the dev menu does (decision record
## 0009): the ship gets neutral input and the right stick and A drive the hub
## through named actions. Every craft and fit is saved at once, so a killed app
## keeps it. It changes only the profile and fitting it was handed (MP-2),
## reads no comfort setting (ARC-3), and sits beside `main.gd` as it reads
## `RunWiring` and the `net/` session's outcome.
##
## Around the seated pilot it shows the home base room (#1298, `HubRoom`,
## decision record 0012) at the head point; the head camera then draws only it.
## `HubLaunch` shows arriving and leaving (#1396, CMF-8): opening, after the end
## screen's fade to black, fades the room in; the launch row glows the cradle
## ship and fades out, then runs the unchanged `launch`, and the mine fades in.
##
## In the room the pages are on its stations (#1299, `HubStations`), chosen by
## the right controller's aim or the stick, with sounds (`HubStationSounds`,
## #1401). The flat panel is kept only for a room that fails to load.

const LOG_PREFIX: String = "[meltdown run]"

## Under the rig origin once `attach` has run; made unattached by `open_for` in
## tests. Shown only when there are no stations (the room did not load).
var panel: HubPanel = null
## The pages on the room's stations; null when the room was not built.
var stations: HubStations = null
## Their sounds (#1401); null without stations.
var sounds: HubStationSounds = null
## The home base room under the rig origin once `attach` has run; null in tests without it.
var room: HubRoom = null
## The open hub's text; null while closed.
var text: HubText = null
## The run the hub launches; kept after closing.
var run: RunWiring = null
## The fitting the hub changes, saved through `run.ship.fittings`.
var fitting: Fitting = null
## Where component files are read; tests may point it elsewhere.
var components_dir: String = ComponentList.COMPONENTS_DIR

## The scene's level start, kept by `open_after` so a launch or resume can
## name the level to fly; null when opened by `open_for` alone (tests).
var level_start: LevelStart = null
var launching: HubLaunch = HubLaunch.new()  # The glow, sound and fades of leaving and arriving (#1396).

var _actions: Dictionary = {}
var _camera: Camera3D = null
var _aim: XRController3D = null


## Hangs the panel, the room and its stations under `rig`; once only.
func attach(rig: Node3D) -> void:
	if panel != null or rig == null:
		return
	panel = HubPanel.new()
	rig.add_child(panel)
	room = HubRoom.new()
	rig.add_child(room)
	if room.is_built():
		stations = HubStations.new(room)
		rig.add_child(stations)
		if not stations.has_stations():
			stations.queue_free()
			stations = null
		else:
			sounds = HubStationSounds.new(stations)
			rig.add_child(sounds)
	_camera = rig.get_node_or_null("Camera") as Camera3D
	_aim = rig.get_node_or_null("RightHand") as XRController3D
	launching.attach(_camera, room if room.is_built() else null)


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
func open_after(p_level_start: LevelStart, session: LocalSession) -> bool:
	if p_level_start.run != null and p_level_start.run.suspended:
		p_level_start.run.suspended = false
		level_start = p_level_start
		return open_for(p_level_start.run)
	if not ends_run(p_level_start, session):
		return false
	level_start = p_level_start
	var config: HubConfig = HubConfig.load_shipped()
	if config.error != "":
		print("%s the hub cannot open, flying the next run: %s" % [LOG_PREFIX, config.error])
		return false
	level_start.source = level_start.run.after_session(session)
	return open_for(level_start.run, config)


## The run waiting in `saves`, or null when there is none or it does not read
## back; a temporary file left by a killed save is never offered.
static func waiting_save(saves: RunSaveStore) -> RunSave:
	if saves == null or not saves.has_save():
		return null
	var saved: RunSave = RunSave.parse_json(FileAccess.get_file_as_string(saves.path))
	return saved if saved.error == "" else null


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
	var model: HubModel = HubModel.create(config, run.profile, roles,
		ComponentList.parse(RunShip.upgrade_texts(components_dir)), tree, fitting, ship_data)
	model.parts = HubPartInfo.load_shipped()
	model.set_waiting(waiting_save(run.saves))
	text = HubText.new(model)
	if stations != null:
		stations.open(text)
		sounds.opened()
	else:
		if panel == null:
			panel = HubPanel.new()
		panel.open(text)
	_actions = {}
	launching.arrive()
	print("%s the hub opens" % LOG_PREFIX)
	return true


## Once per frame, after the dev menu and the shaft panel, with the sampled
## `values`. Returns them unchanged while closed, idle but for the menu button while open.
func read(values: Dictionary) -> Dictionary:
	if not is_open():
		return values
	_actions = DevMenuWiring.actions(values)
	return DevMenuWiring.neutral(values)


## Once per frame with the panel's and room's place `head_point` and the frame's
## `seconds` (closed, it only runs the fade in). True on the frame a resume, or a
## launch whose fade out is dark, passes: saved, closed, and the caller flies the
## run's level. The panel and the fades hold still while the session is paused.
func update(paused: bool, head_point: Transform3D, seconds: float = 0.0) -> bool:
	var due: bool = launching.advance(0.0 if paused else seconds)
	if not is_open():
		return false
	if due:
		launch()
		return true
	panel.transform = head_point
	if room != null:
		room.transform = head_point  # The seat's eye point: only a recentre moves the room.
		if not room.visible:
			room.show_for(_camera)  # Placed first, so it never shows a frame at the rig origin.
	if paused or _actions.is_empty() or launching.is_launching():  # Nothing pressed yet, or leaving.
		return false
	var before: Dictionary = HubSoundTable.state(stations) if stations != null else {}
	if stations != null:
		_point()
	var result: Dictionary = stations.update(_actions) if stations != null else panel.update(_actions)
	if sounds != null:
		sounds.hear(before, result, seconds)
	if result.is_empty() or str(result["reason"]) != "":
		return false
	match str((result["pressed"] as Dictionary).get("action", "")):
		HubText.ACTION_CRAFT:
			save_profile()
		HubText.ACTION_FIT, HubText.ACTION_MOVE, HubText.ACTION_STRIP:
			save_fitting()
		HubText.ACTION_LAUNCH:
			launching.start()  # `launch` runs once the view is dark.
		HubText.ACTION_RESUME:
			return resume_run()
	return false


## The launch row: saves, discards a waiting run, starts a new run after a
## suspend, and closes; the caller flies the run's current level.
func launch() -> void:
	save_profile()
	save_fitting()
	if run.saves != null and run.saves.has_save():
		print("%s a new run scraps the suspended one" % LOG_PREFIX)
		if not run.saves.discard():
			print("%s %s" % [LOG_PREFIX, run.saves.message])
	if not run.active():
		run.start_new()
	if level_start != null:
		level_start.source = run.level_source()
	close()
	print("%s launching from the hub" % LOG_PREFIX)


## The resume row: takes the waiting save and rebuilds the run on it. True,
## with the hub closed, when the caller should fly the run's level; false,
## with one logged line, the save discarded and the hub open, otherwise.
func resume_run() -> bool:
	var saves: RunSaveStore = run.saves if run != null else null
	var saved: RunSave = saves.take() if saves != null else null
	if saved == null or not run.resume(saved):
		var reason: String = "no save store" if saves == null else (saves.message if saved == null else run.error)
		print("%s the suspended run cannot resume, discarding it: %s" % [LOG_PREFIX, reason])
		if saves != null:
			saves.discard()
		if text != null:
			text.model.set_waiting(null)
			text.move(0)
		return false
	save_profile()
	save_fitting()
	if level_start != null:
		level_start.source = run.level_source()
	close()
	launching.left()
	return true


## The scene's fade's opacity: dark while the hub is open, then the fade in.
func alpha() -> float:
	return 1.0 if is_open() else launching.alpha()


func close() -> void:
	text = null
	_actions = {}
	if stations != null:
		stations.close()
	if panel != null:
		panel.close()
	if room != null:
		room.hide_room()


## The refused press's reason the hub shows, or "".
func reason_text() -> String:
	if stations != null:
		return stations.reason_text()
	return panel.reason_text() if panel != null else ""


## Hands the stations the right controller's aim ray in the room's space; a
## controller that is not tracked points at nothing.
func _point() -> void:
	if _aim == null or not _aim.get_is_active() or room == null:
		return
	var to_room: Transform3D = room.transform.affine_inverse()
	stations.point(to_room * _aim.transform.origin, to_room.basis * -_aim.transform.basis.z)


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
