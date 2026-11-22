class_name AcceptanceFittedStart
extends RefCounted

## Scratch stores for a run step (#1057, CRF-4, CRW-1, DEV-6, decision record
## 0005). In a suite:
##
##     {"id": "fitted_start", "run": 12345, "replay": "res://...",
##      "profile": "res://acceptance/fittings/fitted_start_profile.json",
##      "fitting": "res://acceptance/fittings/fitted_start_fitting.json",
##      "checks": ["level_hash"], "expected_level_hash": 123}
##
## `profile` and `fitting` are files in the formats `ProfileStore` and
## `FittingStore` read. The run's levels fly the ship `RunShip` builds from
## them, exactly as `--run` builds it from the pilot's own files; the level
## hash covers the ship's tuning and weapons, so it pins the fitted ship. The
## profile is read once and never saved: the run keeps it in memory, as every
## run step does.
##
## A run step without these fields flies the plain ship file
## (`RunShip.enabled` off), so its pinned hashes do not move when crew joins
## during the step or a pilot's own files sit on the machine.

const KEY_PROFILE: String = "profile"
const KEY_FITTING: String = "fitting"


## Reads `profile` and `fitting` into `step`; "" or the problem, naming the
## field. Runs after `AcceptanceRunStep.parse_step`.
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	for key: String in [KEY_PROFILE, KEY_FITTING]:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		if typeof(value) != TYPE_STRING or str(value) == "":
			return "%s.%s: must be a non-empty path" % [field, key]
		if step.run_seed == AcceptanceStep.NO_SEED:
			return "%s.%s: only used by a run step, which names %s" % [field, key, AcceptanceRunStep.KEY_RUN]
	step.profile_path = str(data.get(KEY_PROFILE, ""))
	step.fitting_path = str(data.get(KEY_FITTING, ""))
	return ""


## Before a run step flies: `run` reads the step's scratch stores, or flies
## the plain ship file when the step names none.
static func begin(run: RunWiring, step: AcceptanceStep) -> void:
	run.ship.enabled = step.profile_path != "" or step.fitting_path != ""
	if step.profile_path != "":
		run.profile = ProfileStore.new(step.profile_path).load_profile()
	if step.fitting_path != "":
		run.ship.fittings = FittingStore.new(step.fitting_path)
