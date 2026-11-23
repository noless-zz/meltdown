extends RefCounted

## The `reactor_wreck_look` acceptance check (#1310, GFX-2, GFX-4, GFX-6): at
## the end of a step whose replay destroyed the reactor, the reactor in the
## main scene is drawn as the machine from the shipped look, breached and
## burning, and the machine adds no light of its own. It reads the view only;
## the step's `final_hash` check holds the simulation to its pinned hash, so
## the new look cannot have changed it (ARC-1, ARC-2).

const CHECK: String = "reactor_wreck_look"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var wiring: MeltdownWiring = runner.main.get("meltdown") if runner.main != null else null
	if wiring == null or wiring.reactor_view == null:
		return [AcceptanceReport.RESULT_FAIL, "the main scene shows no reactor"]
	return judge_view(wiring.reactor_view, measurements)


## [result, message] for `view`, adding the counts it found to `measurements`.
static func judge_view(view: ReactorView, measurements: Dictionary) -> Array:
	var machine: ReactorMachine = view.machine()
	if machine == null:
		return [AcceptanceReport.RESULT_FAIL, "the reactor is drawn without its machine: %s" % view.look_error]
	if not machine.destroyed():
		return [AcceptanceReport.RESULT_FAIL, "the reactor was not drawn as a wreck at the end of the step"]
	var breached: int = 0
	for rib: MeshInstance3D in machine.ribs():
		breached += 0 if rib.visible else 1
	var lights: int = 0
	for node: Node in machine.find_children("*", "Light3D", true, false):
		lights += 1
	var pipes_shown: int = 0
	for pipe: MeshInstance3D in machine.pipes():
		pipes_shown += 1 if pipe.visible else 0
	measurements["reactor_breached_ribs"] = breached
	measurements["reactor_pipes_shown"] = pipes_shown
	measurements["reactor_machine_lights"] = lights
	if breached == 0:
		return [AcceptanceReport.RESULT_FAIL, "the wreck shows every rib whole"]
	if not machine.flames().emitting:
		return [AcceptanceReport.RESULT_FAIL, "the wreck does not burn"]
	if lights != 0:
		return [AcceptanceReport.RESULT_FAIL, "the machine adds %d lights (GFX-4)" % lights]
	return [AcceptanceReport.RESULT_PASS, "wreck with %d ribs breached, %d pipes, burning, no added light" % [breached, pipes_shown]]
