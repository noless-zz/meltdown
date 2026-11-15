extends RefCounted

## Runtime controller models (issue #93, PLT-5, PLT-2, NAM-3): each hand asks
## the OpenXR runtime for its controller model and keeps the generic shape and
## the labels when none arrives, as in every flat or headless run.

const RIG_SCENE: String = "res://xr/xr_rig.tscn"


func _rig() -> Node:
	var scene: PackedScene = load(RIG_SCENE) as PackedScene
	if scene == null:
		return null
	var rig: Node = scene.instantiate()
	rig.call("build")
	return rig


func test_core_render_model_classes_exist() -> String:
	for cls: String in ["OpenXRRenderModelManager", "OpenXRRenderModel", "OpenXRRenderModelExtension"]:
		if not ClassDB.class_exists(cls):
			return "%s is missing from this Godot build" % cls
	return ""


func test_render_model_extension_is_requested() -> String:
	# Without this setting Godot never asks the runtime for XR_EXT_render_model.
	if not bool(ProjectSettings.get_setting("xr/openxr/extensions/render_model", false)):
		return "xr/openxr/extensions/render_model is off in project.godot"
	return ""


func test_each_hand_asks_the_runtime_for_its_model() -> String:
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var message: String = ""
	var want: Dictionary = {
		"left": OpenXRRenderModelManager.RENDER_MODEL_TRACKER_LEFT_HAND,
		"right": OpenXRRenderModelManager.RENDER_MODEL_TRACKER_RIGHT_HAND,
	}
	for hand: String in ["left", "right"]:
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		var manager: OpenXRRenderModelManager = model.runtime_models() if model != null else null
		if manager == null:
			message = "%s hand has no runtime model manager" % hand
		elif manager.tracker != want[hand]:
			message = "%s hand manager tracks %d, want %d" % [hand, manager.tracker, want[hand]]
		elif manager.make_local_to_pose != "default":
			message = "%s hand manager is local to '%s', want the controller's pose 'default'" % [hand, manager.make_local_to_pose]
		if message != "":
			break
	rig.free()
	return message


func test_without_runtime_generic_shape_and_labels_stay() -> String:
	# The flat and headless case: no runtime model arrives. Running the game
	# headless and the Monado smoke job cover the manager inside a live tree.
	var rig: Node = _rig()
	if rig == null:
		return "%s did not load" % RIG_SCENE
	var message: String = ""
	for hand: String in ["left", "right"]:
		if message != "":
			break
		var model: ControllerModel = rig.call("model_for", hand) as ControllerModel
		if model.has_runtime_model():
			message = "%s hand claims a runtime model with no runtime" % hand
		elif not model.generic_shape_visible():
			message = "%s hand generic shape hidden with no runtime model" % hand
		elif model.runtime_models().get_child_count() != 0:
			message = "%s hand manager made models with no runtime" % hand
		elif model.label_texts().is_empty() or not model.labels_visible():
			message = "%s hand lost its labels" % hand
	rig.free()
	return message


func test_runtime_model_replaces_shape_and_keeps_labels() -> String:
	var model: ControllerModel = ControllerModel.new("right")
	model.build()
	model.set_labels({"trigger": "up", "stick_x": "yaw left / right"})
	var first: OpenXRRenderModel = OpenXRRenderModel.new()
	var second: OpenXRRenderModel = OpenXRRenderModel.new()
	var message: String = ""
	model.on_runtime_model_added(first)
	if not model.has_runtime_model() or model.generic_shape_visible():
		message = "runtime model should hide the generic shape"
	elif model.label_texts().size() != 2 or not model.labels_visible():
		message = "labels should stay with a runtime model, got %s" % model.label_texts()
	if message == "":
		model.on_runtime_model_added(second)
		model.on_runtime_model_removed(first)
		if model.generic_shape_visible():
			message = "shape came back while a runtime model remains"
	if message == "":
		model.on_runtime_model_removed(second)
		if model.has_runtime_model() or not model.generic_shape_visible():
			message = "generic shape should return when the runtime removes its model"
	if message == "":
		# A stray removal must not drive the count below zero.
		model.on_runtime_model_removed(second)
		model.on_runtime_model_added(first)
		if model.generic_shape_visible():
			message = "count went negative: one added model left the shape visible"
	first.free()
	second.free()
	model.free()
	return message


func test_rebuild_resets_to_generic_shape() -> String:
	var model: ControllerModel = ControllerModel.new("left")
	model.build()
	var stray: OpenXRRenderModel = OpenXRRenderModel.new()
	model.on_runtime_model_added(stray)
	model.build()
	var message: String = ""
	if model.has_runtime_model() or not model.generic_shape_visible():
		message = "build should start from the generic shape"
	elif model.runtime_models() == null:
		message = "build should recreate the runtime model manager"
	stray.free()
	model.free()
	return message


func test_no_model_files_in_repository() -> String:
	# NAM-3: controller models come only from the runtime at run time.
	var found: Array[String] = []
	_find_models("res://", found)
	if not found.is_empty():
		return "model files committed: %s" % [found]
	return ""


func _find_models(path: String, found: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		var ext: String = file.get_extension().to_lower()
		if ext in ["glb", "gltf", "fbx", "obj", "blend", "dae"]:
			found.append(path.path_join(file))
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_find_models(path.path_join(sub), found)
