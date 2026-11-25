class_name RenderBudget
extends RefCounted

## Draw call, triangle and memory budgets for the steps that measure frame
## times (#1289, PRF-4 to PRF-6). The limits are data (ARC-4), read from
## BUDGET_PATH and checked like `FrameStats`' budget: a broken file is
## reported, never silently replaced by defaults, so it cannot turn a step
## into a pass.
##
## Budget file format:
##
##     {"draw_calls": 150, "triangles": 600000, "memory_mb": 3584}
##
## Triangles count both eyes (PRF-5); memory is in MiB (3584 is PRF-6's 3.5 GB).

const BUDGET_PATH: String = "res://acceptance/checks/render_budget.json"
## The measured quantities, in report order.
const METRICS: Array[String] = ["draw_calls", "triangles", "memory_mb"]

## Limit per metric, by name.
var limits: Dictionary[String, float] = {}
## Why the budget was rejected, or "".
var error: String = ""


static func load_file(path: String = BUDGET_PATH) -> RenderBudget:
	if not FileAccess.file_exists(path):
		return _failed("cannot open %s" % path)
	var budget: RenderBudget = parse_json(FileAccess.get_file_as_string(path))
	if budget.error != "":
		budget.error = "%s: %s" % [path, budget.error]
	return budget


## Every metric must have a limit above zero; unknown keys are rejected so a
## typo cannot switch a budget off.
static func parse_json(text: String) -> RenderBudget:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not METRICS.has(key):
			return _failed("unknown key \"%s\"" % str(key))
	var budget: RenderBudget = RenderBudget.new()
	for key: String in METRICS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)) \
				or float(value) <= 0.0:
			return _failed("key \"%s\" must be a number above 0" % key)
		budget.limits[key] = float(value)
	return budget


static func _failed(message: String) -> RenderBudget:
	var budget: RenderBudget = RenderBudget.new()
	budget.error = message
	return budget
