class_name RunLevelRules
extends RefCounted

## Turns component drops, miner rescue and the alarm on for a level a run
## flies (#1028, #1342, CRF-1, CRF-2, SLV-3, RUN-6).
## The alarm rises by the chosen shaft's `risk.alarm` (`RunWiring.level_alarm_scale`). The rules come from the data files; core opens no
## files, so they are read here and handed to the `Sim` and the `Replay`
## together, so a replay of the level installs the same rules (ARC-2).
##
## A level flown alone (`--level`, `--seed`), the tunnel and every acceptance
## step but a run step that asks for them never come here, so their replays
## and hashes stay as they were.
##
## A rejected file logs one line naming the file and the key and leaves that
## feature off; the level still flies.
##
## A level reached through a chosen shaft weighs its drops by the shaft's
## `reward.tier_weights` (#1000, CRF-7), with each kind's tier read from the
## kind files here. Rejected weights log one line and the drops stay unweighted.

const COMPONENTS_DIR: String = ComponentList.COMPONENTS_DIR
const RESCUE_FILE: String = "res://data/miners/rescue.json"
const ALARM_FILE: String = "res://data/alarm/alarm.json"
const LOG_PREFIX: String = "Meltdown: run level"

## The rules read, or null for a feature that is off.
var components: ComponentPickup = null
var rescue: MinerRescue = null
var alarm: Alarm = null
## The shaft's alarm multiplier the alarm rises by.
var alarm_risk: float = 1.0


## Reads the component kinds and pickup rules from `components_dir` and the
## rescue rules from `rescue_file`. `tier_weights`, when not empty, weighs the
## drops (`RunWiring.level_reward`). The alarm is read from `alarm_file` and
## rises by `p_alarm_risk`.
static func load_files(components_dir: String = COMPONENTS_DIR,
		rescue_file: String = RESCUE_FILE, tier_weights: Array = [],
		alarm_file: String = ALARM_FILE, p_alarm_risk: float = 1.0) -> RunLevelRules:
	var rules: RunLevelRules = RunLevelRules.new()
	rules.components = read_components(components_dir, tier_weights)
	rules.rescue = read_rescue(rescue_file)
	rules.alarm = read_alarm(alarm_file)
	rules.alarm_risk = p_alarm_risk
	return rules


## The pickup rules, or null after logging why. Every kind file must parse too,
## so a broken kind cannot drop under a name nothing knows.
static func read_components(dir: String, tier_weights: Array = []) -> ComponentPickup:
	var texts: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) \
		else PackedStringArray()
	for file: String in files:
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	var kinds: ComponentList = ComponentList.parse(texts)
	if kinds.error != "":
		return _off("components", "%s/%s" % [dir, kinds.error])
	if not texts.has(ComponentList.RULES_FILE):
		return _off("components", "%s: file not found" % dir.path_join(ComponentList.RULES_FILE))
	var rules: ComponentPickup = ComponentPickup.parse_json(texts[ComponentList.RULES_FILE])
	if rules.error != "":
		return _off("components", "%s: %s" % [dir.path_join(ComponentList.RULES_FILE), rules.error])
	if not tier_weights.is_empty():
		var tiers: Dictionary = {}
		for kind: ComponentDef in kinds.kinds:
			tiers[kind.id] = kind.tier
		var problem: String = rules.set_tier_weights(tier_weights, tiers)
		if problem != "":
			print("%s: rejected the shaft's %s; drops are unweighted" % [LOG_PREFIX, problem])
	return rules


## The rescue rules, or null after logging why.
static func read_rescue(path: String) -> MinerRescue:
	if not FileAccess.file_exists(path):
		return _off("rescue", "%s: file not found" % path)
	var rules: MinerRescue = MinerRescue.parse_json(FileAccess.get_file_as_string(path))
	if rules.error != "":
		return _off("rescue", "%s: %s" % [path, rules.error])
	return rules


## The alarm rules, or null after logging why.
static func read_alarm(path: String) -> Alarm:
	if not FileAccess.file_exists(path):
		return _off("alarm", "%s: file not found" % path)
	var rules: Alarm = Alarm.parse_json(FileAccess.get_file_as_string(path))
	if rules.error != "":
		return _off("alarm", "%s: %s" % [path, rules.error])
	return rules


## Gives `session`, before its first tick, these rules and `level`'s miners,
## on its sim and in its replay. Returns `session`.
func install(session: LocalSession, level: LevelDef) -> LocalSession:
	if components != null and session.sim.set_component_rules(components) == "":
		session.replay.component_rules = components
	if rescue != null and session.sim.set_rescue_rules(rescue, level.miners) == "":
		session.replay.rescue_rules = rescue
		session.replay.miners = level.miners.duplicate()
	if alarm != null:
		var problem: String = session.sim.set_alarm_rules(alarm, alarm_risk)
		if problem == "":
			session.replay.alarm_rules = alarm.with_risk(alarm_risk)
		else:
			print("%s: %s; flying with the alarm off" % [LOG_PREFIX, problem])
	return session


static func _off(feature: String, problem: String) -> Variant:
	print("%s: rejected %s; flying with %s off" % [LOG_PREFIX, problem, feature])
	return null
