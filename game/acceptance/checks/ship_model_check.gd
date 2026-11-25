extends RefCounted

## The `ship_model` check (#1362, GFX-2, PRF-4, MP-2, DEV-6, decision record
## 0005), lane-a's file under `acceptance/checks/`. In `suites/m6/ship.json`:
##
##     {"id": "ship_model", "checks": ["no_script_errors", "ship_model"]}
##
## The shipped `view/ship_look.json` must be read without falling back to the
## plain hull, the built ship must stay within `MAX_DRAW_CALLS`, add no light,
## and its engine must brighten with thrust. The ship is then hung in front of
## the scene's camera nose-on and side-on, drawn, and saved as
## `<step id>_front.png` and `<step id>_side.png` under `m6/`, then removed.
## A screenshot that cannot be taken is noted and never fails the step. Whether
## the pictures read as a ship stays human-checked.

const CHECK: String = "ship_model"
const MAX_DRAW_CALLS: int = 12
const SHOT_FOLDER: String = "m6"
## How far in front of the camera the ship hangs: the whole ship in view.
const SHOT_DISTANCE_M: float = 4.0


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var look: ShipLook = ShipLook.load_file()
	var verdict: Array = judge_look(look, measurements)
	if runner != null and runner.main != null:
		measurements["screenshots"] = ", ".join(PackedStringArray(_screenshots(runner, step.id, look)))
	return verdict


## Whether `look` builds a ship within budget that shows its thrust.
static func judge_look(look: ShipLook, measurements: Dictionary) -> Array:
	if look.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the ship look was refused: %s" % look.error]
	var model: ShipModel = ShipModel.create(look)
	var cost: Dictionary = model.cost()
	for key: String in cost:
		measurements["ship_" + key] = cost[key]
	var lights: int = model.find_children("*", "Light3D", true, false).size()
	model.set_thrust(0.0)
	var idle: float = model.engine_energy()
	model.set_thrust(1.0)
	var full: float = model.engine_energy()
	model.free()
	measurements["ship_lights"] = lights
	if int(cost["draw_calls"]) > MAX_DRAW_CALLS:
		return [AcceptanceReport.RESULT_FAIL, "the ship takes %d draw calls, the budget is %d (PRF-4)" % [cost["draw_calls"], MAX_DRAW_CALLS]]
	if lights != 0:
		return [AcceptanceReport.RESULT_FAIL, "the ship adds %d lights (GFX-4)" % lights]
	if full <= idle:
		return [AcceptanceReport.RESULT_FAIL, "the engine glow does not brighten with thrust (%.2f idle, %.2f full)" % [idle, full]]
	return [AcceptanceReport.RESULT_PASS, "%d pieces, %d draw calls, %d materials, %d triangles; engine %.1f idle to %.1f full" % [
		cost["pieces"], cost["draw_calls"], cost["materials"], cost["triangles"], idle, full]]


## The pose that shows the ship to `eye` from `distance` m, nose towards the
## eye when `side` is false, nose to the eye's right when it is true.
static func pose_before(eye: Transform3D, side: bool, distance: float = SHOT_DISTANCE_M) -> Transform3D:
	var turn: Basis = Basis(Vector3.UP, -PI / 2.0) if side else Basis(Vector3.UP, PI)
	return Transform3D(eye.basis * turn, eye * Vector3(0.0, 0.0, -distance))


## The paths saved, or why each view was not.
static func _screenshots(runner: AcceptanceRunner, step_id: String, look: ShipLook) -> Array[String]:
	var notes: Array[String] = []
	var camera: Camera3D = runner.main.get_viewport().get_camera_3d() if runner.main.is_inside_tree() else null
	if camera == null:
		return ["skipped: the scene has no camera"]
	var model: ShipModel = ShipModel.create(look)
	runner.main.add_child(model)
	for view: String in ["front", "side"]:
		var pose: Transform3D = pose_before(camera.global_transform, view == "side")
		model.show_at(pose, 0.5)
		model.global_transform = pose  # The scene root may itself be moved.
		notes.append(_shot(runner, "%s_%s.png" % [step_id, view]))
	runner.main.remove_child(model)
	model.free()
	return notes


static func _shot(runner: AcceptanceRunner, file: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped %s: headless display, nothing is drawn" % file
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped %s: %s" % [file, str(got)]
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(file)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped %s: cannot write %s: %s" % [file, path, error_string(error)]
