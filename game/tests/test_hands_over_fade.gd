extends RefCounted

## The controllers over the dark fade (#1468, CRW-2, RUN-1, CMF-8, PLT-5,
## ARC-3, MP-2). The rule checked is render priority (`HandsOverFade`): every
## drawn surface of both controllers is in the transparent pass above
## `FadeOverlay.RENDER_PRIORITY` and keeps its depth test, at the escape screen,
## the shaft choice and the lost-ship screen, with the generic shape on one hand
## and a runtime model on the other. The labels stay under the fade. In flight
## the materials, the camera's cull mask and the fade's priority are as before.

const FRAME: float = 1.0 / 90.0
const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const PROFILE_PATH: String = "user://t1468_profile.json"
const FITTING_PATH: String = "user://t1468_fitting.json"
const ENTER: Dictionary = {DestroyedWiring.KEYBOARD_BUTTON: true}
## The head camera's mask in flight, as on `main`: every layer.
const FLIGHT_MASK: int = 0xFFFFF


func _clean() -> void:
	for path: String in [PROFILE_PATH, FITTING_PATH]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)


## The main scene flying; with `in_run`, level 1 of a three-level run.
func _main(in_run: bool) -> Node:
	_clean()
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	var level_start: LevelStart = main.get("level_start")
	level_start.source = ""
	if in_run:
		var run: RunWiring = RunWiring.new(12345, ProfileStore.new(PROFILE_PATH), func() -> int: return 77,
			THREE_LEVELS, true)
		run.ship.fittings = FittingStore.new(FITTING_PATH)
		level_start.run = run
		level_start.source = run.level_source()
		(main.get("destroyed") as DestroyedWiring).escape.run = run
	main.call("restart_level")
	return main


func _fly(main: Node, seconds: float, buttons: Dictionary = {}) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	for i: int in ceili(seconds / FRAME):
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)


## Flies until `prompt_shown` (at most 10 s), waits a moment with the button up and presses
## Enter for one frame: a press held from before the prompt does not count.
func _press_after_prompt(main: Node, prompt_shown: Callable) -> void:
	for i: int in ceili(10.0 / FRAME):
		if bool(prompt_shown.call()):
			break
		_fly(main, FRAME)
	_fly(main, 0.1)  # The prompt must see the button up before a press counts.
	_fly(main, FRAME, ENTER)
	_fly(main, FRAME)


## A stand-in for a runtime or Meta model: one mesh whose surface carries an
## opaque material of its own, as a loaded glTF does.
static func _model_mesh() -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.material = StandardMaterial3D.new()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = box
	return node


## Gives the right hand a runtime model; the left keeps the generic shape.
static func _runtime_on_right(main: Node) -> void:
	var model: ControllerModel = main.get_node("XRRig").call("model_for", "right") as ControllerModel
	var arrived: MeshInstance3D = _model_mesh()
	model.runtime_models().add_child(arrived)
	model.on_runtime_model_added(arrived)


## "" when both controllers draw over the fade at `state` and their labels do not.
static func _over(main: Node, state: String) -> String:
	var fade: FadeOverlay = main.get("fade_overlay")
	if fade.get_alpha() < 0.99:
		return "the view is not dark at %s (alpha %.2f)" % [state, fade.get_alpha()]
	for hand: String in ["left", "right"]:
		var model: ControllerModel = main.get_node("XRRig").call("model_for", hand) as ControllerModel
		if not HandsOverFade.is_raised(model):
			return "the %s controller is hidden behind the fade at %s" % [hand, state]
		var labels: String = _labels_under_fade(model)
		if labels != "":
			return "%s at %s" % [labels, state]
	return ""


## "" when no label part of `model` was moved above the fade.
static func _labels_under_fade(model: ControllerModel) -> String:
	var pending: Array[Node] = [model.label_set()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if node.has_meta(HandsOverFade.OVERRIDE_META) or node.has_meta(HandsOverFade.SURFACES_META):
			return "the %s flight label part %s was raised over the fade" % [model.hand, node.name]
	return ""


## "" when nothing of either controller was changed, as in flight.
static func _as_in_flight(main: Node, state: String) -> String:
	var camera: Camera3D = main.get_node("XRRig/Camera") as Camera3D
	if camera.cull_mask != FLIGHT_MASK:
		return "the head camera draws mask %d %s" % [camera.cull_mask, state]
	var fade: FadeOverlay = main.get("fade_overlay")
	if (fade.material_override as BaseMaterial3D).render_priority != Material.RENDER_PRIORITY_MAX - 1:
		return "the fade's priority changed %s" % state
	for hand: String in ["left", "right"]:
		var model: ControllerModel = main.get_node("XRRig").call("model_for", hand) as ControllerModel
		for node: GeometryInstance3D in HandsOverFade.drawn(model):
			if node.has_meta(HandsOverFade.OVERRIDE_META) or node.has_meta(HandsOverFade.SURFACES_META):
				return "the %s controller's %s is still raised %s" % [hand, node.name, state]
			var material: Material = node.material_override
			if material == null and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				material = (node as MeshInstance3D).get_active_material(0)
			if material is BaseMaterial3D and HandsOverFade.draws_over_fade(material):
				return "the %s controller's %s draws over the cockpit %s" % [hand, node.name, state]
	return ""


func test_the_escape_screen_and_the_shaft_choice_draw_both_controllers_over_the_fade() -> String:
	var main: Node = _main(true)
	_runtime_on_right(main)
	_fly(main, 0.1)
	var problem: String = _as_in_flight(main, "in flight")
	var session: LocalSession = main.get("session")
	var end: EscapeEndWiring = (main.get("destroyed") as DestroyedWiring).escape
	if problem == "":
		session.sim.ships[0].escaped = true
		_fly(main, 5.0)
		problem = _over(main, "the escape screen") if end.screen.line_visible() else "no escape screen"
	if problem == "":
		_press_after_prompt(main, func() -> bool: return end.screen.prompt_visible())
		problem = _over(main, "the shaft choice") if end.choice.is_open() else "the shaft choice did not open"
	main.free()
	_clean()
	return problem


func test_the_lost_ship_screen_draws_both_controllers_over_the_fade_and_flight_gets_them_back() -> String:
	var main: Node = _main(false)
	_runtime_on_right(main)
	_fly(main, 0.1)
	var old: LocalSession = main.get("session")
	old.sim.ships[0].hull = 0.0
	_fly(main, 1.2)
	var wiring: DestroyedWiring = main.get("destroyed")
	var problem: String = _over(main, "the lost-ship screen") if wiring.screen.line_visible() else "no lost-ship screen"
	if problem == "":
		_press_after_prompt(main, func() -> bool: return wiring.screen.prompt_visible())
		_fly(main, 2.0)
		if main.get("session") == old:
			problem = "the press did not restart the level"
		else:
			problem = _as_in_flight(main, "after the restart")
	main.free()
	_clean()
	return problem


func test_a_meta_model_and_the_generic_shape_are_raised_and_put_back() -> String:
	var model: ControllerModel = ControllerModel.new("left")
	model.build()
	var vendor: Node3D = Node3D.new()
	vendor.name = ControllerModel.VENDOR_MODEL_NAME
	var mesh: MeshInstance3D = _model_mesh()
	vendor.add_child(mesh)
	model.add_child(vendor)
	var shipped: Material = (mesh.mesh as BoxMesh).material
	var handle: MeshInstance3D = model.get_node("Handle") as MeshInstance3D
	var body: Material = handle.material_override
	var problem: String = ""
	var count: int = HandsOverFade.raise(model)
	if not HandsOverFade.is_raised(model):
		problem = "raising left a surface under the fade"
	elif HandsOverFade.raise(model) != 0 or count == 0:
		problem = "raising again changed %d surfaces (first %d)" % [HandsOverFade.raise(model), count]
	elif mesh.get_active_material(0) == shipped or handle.material_override == body:
		problem = "the shipped materials were edited in place instead of copied"
	elif (shipped as BaseMaterial3D).render_priority != 0:
		problem = "the model's own material was changed"
	if problem == "":
		HandsOverFade.lower(model)
		if mesh.get_active_material(0) != shipped or mesh.get_surface_override_material(0) != null:
			problem = "lowering did not give the Meta model its material back"
		elif handle.material_override != body:
			problem = "lowering did not give the generic shape its material back"
	model.free()
	return problem


func test_the_raised_copy_keeps_its_depth_test_and_sits_above_the_fade() -> String:
	var copy: BaseMaterial3D = HandsOverFade.over(StandardMaterial3D.new())
	if copy.no_depth_test:
		return "the raised copy would draw through the cockpit"
	if copy.render_priority <= FadeOverlay.RENDER_PRIORITY:
		return "the raised copy is not above the fade (%d)" % copy.render_priority
	if copy.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return "the raised copy stays in the opaque pass, under the fade"
	if FadeOverlay.RENDER_PRIORITY != Material.RENDER_PRIORITY_MAX - 1:
		return "the fade's priority is %d, not one below the top" % FadeOverlay.RENDER_PRIORITY
	return ""


func test_nothing_is_raised_without_a_rig_and_lowering_waits_for_a_raise() -> String:
	var hands: HandsOverFade = HandsOverFade.new()
	hands.update(true)
	if not hands.raised():
		return "an end screen without a rig did not count as raised"
	hands.update(false)
	if hands.raised():
		return "the hands stayed raised after the screen closed"
	return ""
