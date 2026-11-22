extends RefCounted

## The run sweep's fitted ship (#1091, CRW-3, CRF-4, CRW-1): the maxed fixture
## builds a ship whose primary weapon and shield differ from the plain ship
## file's; the fixture really is maxed (every upgrade crafted, every crew cap
## reached); a missing or unreadable profile or fitting stops with a message
## naming it; the plain sweep for run seed 12345 prints what it printed before
## this issue; level 1's escape and hull reach the `MELTDOWN_BOT_SHIP` line.

const RunSweep := preload("res://tests/bot_run_sweep.gd")
const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Ship := preload("res://tests/bot_sweep_ship.gd")
const Levels := preload("res://tests/bot_sweep_levels.gd")
const PROFILE: String = "res://tests/fixtures/maxed_profile.json"
const FITTING: String = "res://tests/fixtures/maxed_fitting.json"
const SCRATCH: String = "user://test_bot_sweep_fitted_bad.json"
## Run seed 12345 flown by the plain ship file, as printed on main before #1091.
const PINNED_PLAIN_LINE: String = 'MELTDOWN_BOT_RUN {"seed":12345,"planned":5,"flown":3,"escaped":2,"ended":"LOST ship destroyed"}'
const PINNED_PLAIN_SUMMARY: String = 'MELTDOWN_BOT_RUNS {"runs":1,"completed":0,"rate":0.0000,"levels_flown":3,"levels_escaped":2}'


static func _result(escaped: bool, hull: float) -> EscapeSweep.SeedResult:
	var flown: EscapeSweep.SeedResult = EscapeSweep.SeedResult.new()
	flown.escaped = escaped
	flown.outcome = "ESCAPED" if escaped else "RUNNING"
	flown.destroyed = hull <= 0.0
	flown.hull = hull
	return flown


func test_maxed_fixture_differs_from_the_plain_ship() -> String:
	var built: Dictionary = Ship.fitted(PROFILE, FITTING)
	if built["error"] != "":
		return "fixture rejected: %s" % built["error"]
	var fitted: ShipTuning = built["tuning"]
	var plain: ShipTuning = Levels.new().tuning
	if fitted.loadout.primary_ids[0] == plain.loadout.primary_ids[0]:
		return "primary slot is %s on both ships" % plain.loadout.primary_ids[0]
	if fitted.loadout.primary_ids[0] != "arc_lance":
		return "fitted primary is %s, expected arc_lance" % fitted.loadout.primary_ids[0]
	if is_equal_approx(fitted.max_shield, plain.max_shield):
		return "shield is %.2f on both ships" % plain.max_shield
	# glass_core_shield's 1.4 on the ship file's 50, then the crew's cap of 25.
	if not is_equal_approx(fitted.max_shield, plain.max_shield * 1.4 + 25.0):
		return "fitted shield %.2f, expected %.2f" % [fitted.max_shield, plain.max_shield * 1.4 + 25.0]
	return ""


func test_maxed_profile_crafts_every_upgrade_and_reaches_every_cap() -> String:
	var profile: Profile = ProfileStore.new(PROFILE).load_profile()
	var upgrades: Array[String] = []
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			upgrades.append(file.get_basename())
	for id: String in upgrades:
		if not profile.crafted.has(id):
			return "the maxed profile has not crafted %s" % id
	var roles: CrewRoles = CrewRoles.parse_json(FileAccess.get_file_as_string(CrewRoles.ROLES_FILE))
	var totals: Dictionary = CrewBenefits.totals(profile, roles)
	for stat: String in CrewRoles.STAT_MAX:
		if int(totals.get(stat, 0)) != roles.cap(stat):
			return "crew gives %s %d, the cap is %d" % [stat, int(totals.get(stat, 0)), roles.cap(stat)]
	return ""


func test_missing_profile_or_fitting_names_the_path() -> String:
	var missing: String = "res://tests/fixtures/no_such_profile.json"
	var built: Dictionary = Ship.fitted(missing, FITTING)
	if built["tuning"] != null or not String(built["error"]).contains(missing):
		return "missing profile gave \"%s\"" % built["error"]
	var no_fitting: String = "res://tests/fixtures/no_such_fitting.json"
	built = Ship.fitted(PROFILE, no_fitting)
	if built["tuning"] != null or not String(built["error"]).contains(no_fitting):
		return "missing fitting gave \"%s\"" % built["error"]
	return ""


func test_unreadable_profile_or_fitting_names_the_path() -> String:
	var file: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var bad_profile: Dictionary = Ship.fitted(SCRATCH, FITTING)
	var bad_fitting: Dictionary = Ship.fitted(PROFILE, SCRATCH)
	DirAccess.remove_absolute(SCRATCH)
	if bad_profile["tuning"] != null or not String(bad_profile["error"]).begins_with("profile " + SCRATCH):
		return "unreadable profile gave \"%s\"" % bad_profile["error"]
	if bad_fitting["tuning"] != null or not String(bad_fitting["error"]).begins_with("fitting " + SCRATCH):
		return "unreadable fitting gave \"%s\"" % bad_fitting["error"]
	return ""


func test_profile_and_fitting_options_go_together() -> String:
	var both: Dictionary = RunSweep.parse_options(PackedStringArray([
			"--runs=20", "--profile=" + PROFILE, "--fitting=" + FITTING]))
	if both["error"] != "" or both["profile"] != PROFILE or both["fitting"] != FITTING or both["runs"] != 20:
		return "parsed %s" % [both]
	var alone: Dictionary = RunSweep.parse_options(PackedStringArray(["--profile=" + PROFILE]))
	if alone["error"] == "":
		return "--profile without --fitting was accepted"
	var plain: Dictionary = RunSweep.parse_options(PackedStringArray([]))
	if plain["error"] != "" or plain["profile"] != "" or plain["runs"] != 100 or plain["first"] != 1:
		return "no options parsed as %s" % [plain]
	return ""


func test_plain_report_unchanged_for_the_same_seed() -> String:
	var result: Dictionary = RunSweep.run(12345, 1)
	if not result["errors"].is_empty():
		return "errors: %s" % [result["errors"]]
	if result["lines"] != [PINNED_PLAIN_LINE]:
		return "plain line %s, pinned %s" % [result["lines"], PINNED_PLAIN_LINE]
	if RunSweep.summary(result) != PINNED_PLAIN_SUMMARY:
		return "plain summary %s, pinned %s" % [RunSweep.summary(result), PINNED_PLAIN_SUMMARY]
	return ""


func test_level_one_escape_and_hull_reach_the_ship_line() -> String:
	# Run seed 1 escapes level 1 with 80 hull and every level after; run seed 2
	# is destroyed on level 1.
	var stub: Callable = func(run_seed: int, _index: int, _level_seed: int) -> EscapeSweep.SeedResult:
		return _result(run_seed == 1, 80.0 if run_seed == 1 else 0.0)
	var result: Dictionary = RunSweep.run(1, 2, stub, null, RunSweep.RUN_TAG + RunSweep.FITTED_SUFFIX)
	var expected: String = 'MELTDOWN_BOT_SHIP {"ship":"fitted","runs":2,"finished":1,"level1_escapes":1,"level1_mean_hull":40.00}'
	if RunSweep.ship_line("fitted", result) != expected:
		return "ship line %s, expected %s" % [RunSweep.ship_line("fitted", result), expected]
	if not String(result["lines"][0]).begins_with("MELTDOWN_BOT_RUN_FITTED {"):
		return "fitted run line %s" % result["lines"][0]
	return ""
