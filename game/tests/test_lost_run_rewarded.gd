extends RefCounted

## A lost run still leaves its reward (#1194, RUN-7, CRF-2, CRW-1, ARC-2,
## DEV-6): run 12345 escapes level 1 with components and two rescued miners,
## is lost on level 2, and the profile on disk, the hub built from it and the
## next run's ship all still have what level 1 banked. Driven through
## `RunWiring.after_level`, the path the end screen's restart press takes; no
## scene. The feel of it stays on gate #950.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
const DIR: String = "user://t1194_lost_run"
## A fixed copy of the roles (as in `test_run_crew_joins.gd`), so the crew
## pinned below does not move when the shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""
## Carried out of level 1: exactly the shipped `aim_assist` upgrade's cost.
const LEVEL_1_CARRY: Dictionary = {"scrap_alloy": 2, "cell_salts": 3}
const LEVEL_1_RESCUED: int = 2
## Carried on level 2 when the ship is destroyed; none of it may reach the profile.
const LEVEL_2_CARRY: Dictionary = {"core_glass": 2, "scrap_alloy": 5}
const UPGRADE_COVERED: String = "aim_assist"


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path: String = "%s/%s.json" % [DIR, name]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


func _wiring(store: ProfileStore) -> RunWiring:
	var run: RunWiring = RunWiring.new(RUN_SEED, store, func() -> int: return NEXT_RUN_SEED,
		THREE_LEVELS, false)
	run.use_roles(ROLES_TEXT)
	return run


func _roles() -> CrewRoles:
	return CrewRoles.parse_json(ROLES_TEXT)


func _member(id: String, role: String) -> Dictionary:
	return {Profile.CREW_ID: id, Profile.CREW_ROLE: role}


## The crew level 1's two rescued miners join as (pinned in `test_run_crew_joins.gd`).
func _joined() -> Array[Dictionary]:
	return [_member("crew-1", "surveyor"), _member("crew-2", "shield_tech")]


## Escape level 1, lose level 2, as the end screen's restart presses would.
## Returns the run, or null with `problems` filled when a step went wrong.
func _escape_then_lose(path: String, problems: Array[String]) -> RunWiring:
	var run: RunWiring = _wiring(ProfileStore.new(path))
	if run.error != "" or run.state.level_index != 0:
		problems.append("the run did not start on level 1: '%s'" % run.error)
		return null
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, LEVEL_1_CARRY.duplicate(), LEVEL_1_RESCUED)
	if run.error != "" or run.state.level_index != 1:
		problems.append("the escape did not move to level 2: '%s'" % run.error)
		return null
	run.after_level(ExitRule.Outcome.RUNNING, 0.0, LEVEL_2_CARRY.duplicate(), 1)
	if run.ended == null or not run.ended.lost:
		problems.append("the destroyed ship did not lose the run")
		return null
	return run


func _hub(profile: Profile) -> HubModel:
	return HubModel.create(HubConfig.load_shipped(), profile, _roles(),
		ComponentList.parse(RunShip.upgrade_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(RunShip.upgrade_texts(UpgradeTree.UPGRADES_DIR)), Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(RunShip.SHIP_FILE)))


func test_the_saved_profile_keeps_level_1_and_drops_level_2() -> String:
	var problems: Array[String] = []
	var path: String = _path("saved")
	if _escape_then_lose(path, problems) == null:
		return "\n".join(problems)
	var read: Profile = ProfileStore.new(path).load_profile()
	for id: String in LEVEL_1_CARRY:
		if read.count_of(id) != LEVEL_1_CARRY[id]:
			problems.append("%s: %d banked, expected %d" % [id, read.count_of(id), LEVEL_1_CARRY[id]])
	if read.count_of("core_glass") != 0:
		problems.append("the lost level's core_glass reached the profile")
	if read.crew != _joined():
		problems.append("crew %s, expected %s" % [read.crew, _joined()])
	return "\n".join(problems)


func test_the_hub_lists_the_reward_and_offers_what_it_covers() -> String:
	var problems: Array[String] = []
	var path: String = _path("hub")
	if _escape_then_lose(path, problems) == null:
		return "\n".join(problems)
	var model: HubModel = _hub(ProfileStore.new(path).load_profile())
	for problem: String in [model.config.error, model.components.error, model.tree.error]:
		if problem != "":
			return "shipped hub data rejected: %s" % problem
	var listed: Dictionary = {}
	for row: Dictionary in model.store():
		listed[row["id"]] = row["count"]
	if listed != LEVEL_1_CARRY:
		problems.append("the store lists %s, expected %s" % [listed, LEVEL_1_CARRY])
	var roles: Array[String] = []
	for member: Dictionary in model.crew():
		roles.append(member["role"])
	if roles != ["surveyor", "shield_tech"]:
		problems.append("the crew page lists %s" % [roles])
	if not model.craftable().has(UPGRADE_COVERED):
		problems.append("%s is not craftable; craftable: %s" % [UPGRADE_COVERED, model.craftable()])
	return "\n".join(problems)


## The next run is launched from the saved profile, as a fresh launch would read
## it, and its ship is built by `RunShip` through `RunStartShip.build`, the
## builder `fitted_start` checks.
func test_the_next_run_starts_with_the_crew_benefit() -> String:
	var problems: Array[String] = []
	var path: String = _path("next_run")
	if _escape_then_lose(path, problems) == null:
		return "\n".join(problems)
	var next: RunWiring = _wiring(ProfileStore.new(path))
	if not next.active() or next.state.level_index != 0:
		return "the next run did not start on its first level"
	var plain: ShipTuning = LocalSession.load_tuning(RunShip.SHIP_FILE, LocalSession.WEAPON_DIR)
	var fitted: ShipTuning = next.ship.tuning_for(next.profile, next.roles)
	if fitted == null or plain == null:
		return "a ship tuning was rejected"
	if fitted.max_shield != plain.max_shield + 5.0:
		return "the next run's shield is %s, expected the ship file's %s plus the shield technician's 5" % [
			fitted.max_shield, plain.max_shield]
	return ""


func test_the_same_run_saves_the_same_profile_text_twice() -> String:
	var problems: Array[String] = []
	var first: String = _path("first")
	var second: String = _path("second")
	if _escape_then_lose(first, problems) == null or _escape_then_lose(second, problems) == null:
		return "\n".join(problems)
	var a: String = FileAccess.get_file_as_string(first)
	var b: String = FileAccess.get_file_as_string(second)
	if a == "" or a != b:
		return "two runs saved different profiles:\n%s\n%s" % [a, b]
	return ""
