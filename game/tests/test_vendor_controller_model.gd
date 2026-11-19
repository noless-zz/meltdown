extends RefCounted

## Meta controller models through the Godot OpenXR Vendors plugin (issue #10,
## PLT-2, PLT-5). The unit tests run without the plugin, as every non-Quest
## build does: no vendor node is made and the generic shape stays. The plugin's
## "model loaded" signal is driven by hand.


func test_meta_render_model_extension_is_requested() -> String:
	# The plugin only enables XR_FB_render_model (and the export only adds its
	# permission) when this setting is on.
	if not bool(ProjectSettings.get_setting(ControllerModel.VENDOR_MODEL_SETTING, false)):
		return "%s is off in project.godot" % ControllerModel.VENDOR_MODEL_SETTING
	return ""


func test_without_plugin_no_vendor_node_and_shape_stays() -> String:
	if ClassDB.class_exists(ControllerModel.VENDOR_MODEL_CLASS):
		return ""  # A local clone with the plugin fetched; CI has none.
	var model: ControllerModel = ControllerModel.new("left")
	model.build()
	var message: String = ""
	if model.vendor_model() != null:
		message = "a vendor model node was made without the plugin"
	elif model.has_runtime_model() or not model.generic_shape_visible():
		message = "the generic shape should stay without the plugin"
	model.free()
	return message


func test_vendor_model_replaces_shape_and_keeps_labels() -> String:
	var model: ControllerModel = ControllerModel.new("right")
	model.build()
	model.set_labels({"trigger": "up"})
	model.on_vendor_model_loaded()
	var message: String = ""
	if not model.has_runtime_model() or model.generic_shape_visible():
		message = "the Meta model should hide the generic shape"
	elif model.label_texts().size() != 1 or not model.labels_visible():
		message = "labels should stay with the Meta model"
	elif model.runtime_models().visible:
		message = "the XR_EXT_render_model models should hide behind the Meta model"
	model.free()
	return message


func test_vendor_model_outlasts_ext_model_removal() -> String:
	var model: ControllerModel = ControllerModel.new("left")
	model.build()
	var ext_model: OpenXRRenderModel = OpenXRRenderModel.new()
	model.on_runtime_model_added(ext_model)
	model.on_vendor_model_loaded()
	model.on_runtime_model_removed(ext_model)
	var message: String = ""
	if model.generic_shape_visible() or not model.has_runtime_model():
		message = "the generic shape came back while the Meta model is shown"
	ext_model.free()
	model.free()
	return message


func test_rebuild_forgets_vendor_model() -> String:
	var model: ControllerModel = ControllerModel.new("left")
	model.build()
	model.on_vendor_model_loaded()
	model.build()
	var message: String = ""
	if model.has_runtime_model() or not model.generic_shape_visible():
		message = "build should start from the generic shape"
	model.free()
	return message
