class_name ControllerModel
extends Node3D

## A simple, generic controller shape for one hand, built from primitive
## meshes, with a floating label beside each bound control (PLT-5, CMF-4).
##
## The shape is original and deliberately plain: a handle, a head with a
## stick, two face buttons, a small menu button and a trigger. When the OpenXR runtime supplies its
## own model of the controller (XR_EXT_render_model, #93), that model is shown
## instead and the generic shape is hidden; it comes back if the runtime
## removes its model. The runtime's model is fetched at run time and never
## stored in the repository (NAM-3). Quest builds also carry the Godot OpenXR
## Vendors plugin (#10), whose Meta render-model node (XR_FB_render_model) is
## tried as well, since the Quest runtime offers no XR_EXT_render_model models.
## Labels stay in both cases and are
## billboarded so they face the player from any hand angle. Their leader lines
## end on the generic shape's controls, or on the runtime model's own parts
## while it is shown (#652, see `ControllerAnchors`). Nothing here reads
## or writes input or ship state; the rig hands it the words to show (ARC-3).

## Where each control's label sits; see `ControlLabelSet` (#147).
const LABEL_POSITIONS: Dictionary = ControlLabelSet.LABEL_POSITIONS

const HANDLE_RADIUS: float = 0.018
const HANDLE_LENGTH: float = 0.10
## The handle leans back from the head, as on most grips.
const HANDLE_TILT_DEGREES: float = 25.0
const HEAD_SIZE: Vector3 = Vector3(0.05, 0.025, 0.06)
const HEAD_OFFSET: Vector3 = Vector3(0.0, 0.015, -0.02)
const STICK_RADIUS: float = 0.009
const STICK_HEIGHT: float = 0.012
const STICK_OFFSET: Vector3 = Vector3(-0.01, 0.033, -0.03)
const BUTTON_RADIUS: float = 0.006
const BUTTON_HEIGHT: float = 0.004
const BUTTON_UPPER_OFFSET: Vector3 = Vector3(0.012, 0.029, -0.015)
const BUTTON_LOWER_OFFSET: Vector3 = Vector3(0.012, 0.029, 0.002)
## Behind the stick, towards the grip. Only the left one is read (reset, #162);
## on the right hand the same place is the system button.
const MENU_RADIUS: float = 0.004
const MENU_OFFSET: Vector3 = Vector3(-0.01, 0.029, 0.012)
const TRIGGER_SIZE: Vector3 = Vector3(0.012, 0.025, 0.012)
const TRIGGER_OFFSET: Vector3 = Vector3(0.0, -0.01, -0.05)
const DETAIL_COLOR: Color = Color(0.15, 0.15, 0.15)
## Hand-local point of each control on the right hand, where its label's
## leader line ends: the top of the stick, the face of each button, the
## trigger, and the outer side of the handle for the grip.
const CONTROL_POINTS: Dictionary = {
	"stick_x": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"stick_y": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"stick_click": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"button_upper": BUTTON_UPPER_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"button_lower": BUTTON_LOWER_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"menu": MENU_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"trigger": TRIGGER_OFFSET,
	"grip": Vector3(HANDLE_RADIUS, -HANDLE_LENGTH * 0.4, 0.01),
}
## Child names of the generic shape, hidden while a runtime model is shown.
const GENERIC_PARTS: PackedStringArray = ["Handle", "Head", "Stick", "ButtonUpper", "ButtonLower", "Menu", "Trigger"]
## The node that asks the runtime for this hand's controller model.
const RUNTIME_MODELS_NAME: String = "RuntimeModels"
## The vendors plugin's Meta render-model node. Only the Quest export fetches
## the plugin, so the class is looked up by name and may be missing.
const VENDOR_MODEL_CLASS: String = "OpenXRFbRenderModel"
const VENDOR_MODEL_NAME: String = "VendorModel"
const VENDOR_MODEL_SETTING: String = "xr/openxr/extensions/meta/render_model"
const VENDOR_MODEL_LOADED: StringName = &"openxr_fb_render_model_loaded"

## `"left"` or `"right"`; picks which way the shape and labels mirror.
var hand: String = "right"
var body_color: Color = Color(0.5, 0.5, 0.5)
## The pose the parent XRController3D follows. Runtime models arrive in
## XROrigin3D space, so the manager must undo this pose to sit under the hand.
var pose_name: StringName = &"default"
var show_labels: bool = true:
	set(value):
		show_labels = value
		if _labels_root != null:
			_labels_root.visible = value

var _labels_root: ControlLabelSet = null
## Runtime models shown now; the generic shape is visible only at zero.
var _runtime_model_count: int = 0
## True once the vendors plugin loaded this hand's Meta model; it has no
## removal signal, and a new session reloads the model in place.
var _vendor_model_shown: bool = false
## The labels last set, kept so a model arriving later moves their lines.
var _labels: Dictionary = {}
var _anchors: ControllerAnchors = null
## Where the leader lines end now; see `ControllerAnchors.SOURCE_*`.
var _anchor_source: String = ControllerAnchors.SOURCE_GENERIC
## The interaction profile the runtime model belongs to; empty asks the
## hand's tracker. Public so the tests can set it without a runtime.
var runtime_profile: String = ""


func _init(p_hand: String = "right", p_body_color: Color = Color(0.5, 0.5, 0.5)) -> void:
	hand = p_hand
	body_color = p_body_color


## Builds the shape and an empty label holder. Safe to call again.
func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	ControllerShape.add_generic(self, hand, body_color)
	_labels_root = ControlLabelSet.new(hand)
	_labels_root.visible = show_labels
	add_child(_labels_root)
	_runtime_model_count = 0
	_vendor_model_shown = false
	_labels = {}
	_anchor_source = ControllerAnchors.SOURCE_GENERIC
	_add_runtime_models()
	_add_vendor_model()


## True while the runtime supplies this hand's model and the generic shape is hidden.
func has_runtime_model() -> bool:
	return _runtime_model_count > 0 or _vendor_model_shown


## True when the generic shape is drawn (every part visible).
func generic_shape_visible() -> bool:
	for part: String in GENERIC_PARTS:
		var node: Node3D = get_node_or_null(part) as Node3D
		if node == null or not node.visible:
			return false
	return true


## The runtime model manager for this hand, or null before `build`.
func runtime_models() -> OpenXRRenderModelManager:
	return get_node_or_null(RUNTIME_MODELS_NAME) as OpenXRRenderModelManager


## The vendors plugin's model node for this hand, or null without the plugin.
func vendor_model() -> Node3D:
	return get_node_or_null(VENDOR_MODEL_NAME) as Node3D


## Replaces the labels with `labels` (control without hand prefix -> text,
## as `ControlLabels.for_hand` gives). Controls with no known position are
## skipped.
func set_labels(labels: Dictionary) -> void:
	if _labels_root == null:
		build()
	_labels = labels.duplicate()
	_move_leaders()


## Hand-local point of each control on the right hand, where its leader line
## ends: the generic shape's, or the runtime model's parts while it is shown.
func control_points() -> Dictionary:
	if not has_runtime_model():
		_anchor_source = ControllerAnchors.SOURCE_GENERIC
		return CONTROL_POINTS
	if _anchors == null:
		_anchors = ControllerAnchors.load_file()
		if _anchors.error != "":
			push_warning("label anchors use the generic shape: %s" % _anchors.error)
	var root: Node = vendor_model() if _vendor_model_shown else runtime_models()
	var profile: String = runtime_profile if runtime_profile != "" else ControllerAnchors.tracker_profile(hand)
	var result: Dictionary = _anchors.resolve(root, self, hand, profile, CONTROL_POINTS)
	_anchor_source = result["source"]
	return result["points"]


## `ControllerAnchors.SOURCE_*` naming where the leader lines end now.
func anchor_source() -> String:
	return _anchor_source


## Control (without hand prefix) -> the text of its label, as shown now.
func label_texts() -> Dictionary:
	if _labels_root == null:
		return {}
	return _labels_root.texts()


## The labels of this hand, or null before `build`.
func label_set() -> ControlLabelSet:
	return _labels_root


## Fades the labels and their leader lines; 0 is invisible, 1 fully shown.
func set_label_alpha(value: float) -> void:
	if _labels_root != null:
		_labels_root.set_alpha(value)


func label_alpha() -> float:
	return _labels_root.alpha() if _labels_root != null else 1.0


## True when the labels would be drawn (the model itself may still be hidden).
func labels_visible() -> bool:
	return _labels_root != null and _labels_root.visible


## Connected to the manager's `render_model_added`; public to the tests,
## which have no runtime to send it.
func on_runtime_model_added(_render_model: Node3D) -> void:
	_runtime_model_count += 1
	_show_generic(false)
	_move_leaders()


## Connected to the manager's `render_model_removed`.
func on_runtime_model_removed(_render_model: Node3D) -> void:
	_runtime_model_count = maxi(_runtime_model_count - 1, 0)
	_show_generic(not has_runtime_model())
	_move_leaders()


## Connected to the vendor model's `openxr_fb_render_model_loaded`; public to
## the tests, which have no plugin. The Meta model wins over any
## XR_EXT_render_model one so the hand never shows two controllers.
func on_vendor_model_loaded() -> void:
	_vendor_model_shown = true
	_show_generic(false)
	var manager: OpenXRRenderModelManager = runtime_models()
	if manager != null:
		manager.visible = false
	_move_leaders()


func _move_leaders() -> void:
	if _labels_root != null:
		_labels_root.set_labels(_labels, control_points())


func _add_runtime_models() -> void:
	# Without an OpenXR session (flat, headless, Monado) the manager stays
	# empty and the generic shape remains.
	var manager: OpenXRRenderModelManager = OpenXRRenderModelManager.new()
	manager.name = RUNTIME_MODELS_NAME
	manager.tracker = (
		OpenXRRenderModelManager.RENDER_MODEL_TRACKER_LEFT_HAND
		if hand == "left"
		else OpenXRRenderModelManager.RENDER_MODEL_TRACKER_RIGHT_HAND
	)
	manager.make_local_to_pose = String(pose_name)
	manager.render_model_added.connect(on_runtime_model_added)
	manager.render_model_removed.connect(on_runtime_model_removed)
	add_child(manager)


func _add_vendor_model() -> void:
	if not ClassDB.class_exists(VENDOR_MODEL_CLASS):
		return
	if not bool(ProjectSettings.get_setting(VENDOR_MODEL_SETTING, false)):
		return
	var node: Node3D = ClassDB.instantiate(VENDOR_MODEL_CLASS) as Node3D
	if node == null:
		return
	node.name = VENDOR_MODEL_NAME
	# The plugin's enum: 0 is the left controller, 1 the right.
	node.set("render_model_type", 0 if hand == "left" else 1)
	node.connect(VENDOR_MODEL_LOADED, on_vendor_model_loaded)
	add_child(node)


func _show_generic(shown: bool) -> void:
	for part: String in GENERIC_PARTS:
		var node: Node3D = get_node_or_null(part) as Node3D
		if node != null:
			node.visible = shown

