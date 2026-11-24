extends RefCounted

## The `fire_debris_look` acceptance check (#1331): it passes on burning fire
## with particles, and fails without the effects look or with no fire burning.
## The m6 `reactor_and_fire` step lists it; that step runs through the
## acceptance runner (`--acceptance=m6`), where its pinned hashes hold the
## simulation unchanged (ARC-1, ARC-2).

const CHECK_SCRIPT: String = "res://acceptance/checks/debris_look_check.gd"


func _judge(view: DebrisView) -> Array:
	var script: GDScript = load(CHECK_SCRIPT)
	return script.call("judge_view", view, {})


func _burn(view: DebrisView, burning: bool) -> void:
	view.show_debris([Vector3.ZERO, Vector3(0, 0, -10)] as Array[Vector3], [1.5, 2.0] as Array[float],
		[false, true] as Array[bool], [false, false] as Array[bool],
		[0.0 if burning else 5.0, 0.0] as Array[float], [] as Array[Vector3],
		[MeltdownFire.KIND_FIRE, MeltdownFire.KIND_SOLID] as Array[String], 60)


func test_registers_its_name_and_the_step_lists_it() -> String:
	var script: GDScript = load(CHECK_SCRIPT)
	var judges: Dictionary = script.call("judges")
	if not judges.has("fire_debris_look"):
		return "the check is not registered under fire_debris_look"
	for suite: AcceptanceSuite in AcceptanceSuite.load_named("m6"):
		for step: AcceptanceStep in suite.steps:
			if step.id == "reactor_and_fire":
				return "" if step.checks.has("fire_debris_look") else "reactor_and_fire does not list fire_debris_look"
	return "m6 has no reactor_and_fire step"


func test_passes_on_burning_fire_with_particles() -> String:
	var view: DebrisView = DebrisView.new()
	_burn(view, true)
	var result: Array = _judge(view)
	view.free()
	return "" if result[0] == AcceptanceReport.RESULT_PASS else "burning fire failed: %s" % result[1]


func test_fails_when_no_fire_burns() -> String:
	var view: DebrisView = DebrisView.new()
	_burn(view, false)
	var result: Array = _judge(view)
	view.free()
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "no fire burning passed"


func test_fails_without_the_effects_look() -> String:
	var view: DebrisView = DebrisView.new()
	view.load_effects("user://test_debris_look_check_missing.json")
	_burn(view, true)
	var result: Array = _judge(view)
	view.free()
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "today's look passed as the new one"

